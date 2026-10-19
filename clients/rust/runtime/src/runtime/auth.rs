use std::fmt;

use crate::runtime::Error;

/// A credential requiring explicit access. Cloning does not zeroize its storage.
#[derive(Clone, PartialEq, Eq)]
pub struct SecretString(String);

impl SecretString {
    pub fn expose_secret(&self) -> &str {
        &self.0
    }
}

impl From<String> for SecretString {
    fn from(value: String) -> Self {
        Self(value)
    }
}

impl From<&str> for SecretString {
    fn from(value: &str) -> Self {
        Self(value.to_owned())
    }
}

impl fmt::Debug for SecretString {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str("[REDACTED]")
    }
}

impl fmt::Display for SecretString {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str("[REDACTED]")
    }
}

#[non_exhaustive]
pub enum TokenStep {
    Complete {
        token: SecretString,
    },
    Challenge {
        token: SecretString,
        next_action: String,
    },
}

impl TokenStep {
    pub fn from_parts(
        complete: bool,
        token: Option<String>,
        next_action: Option<String>,
        known_steps: &[&str],
    ) -> Result<Self, Error> {
        let token = token
            .filter(|token| !token.trim().is_empty())
            .ok_or_else(|| Error::protocol(None, "authentication response is missing its token"))?;
        if complete {
            if next_action
                .as_ref()
                .is_some_and(|action| !action.is_empty())
            {
                return Err(Error::protocol(
                    None,
                    "completed authentication contains a continuation",
                ));
            }
            Ok(Self::Complete {
                token: token.into(),
            })
        } else {
            let next_action = next_action
                .filter(|action| !action.is_empty())
                .ok_or_else(|| {
                    Error::protocol(None, "authentication response is missing its continuation")
                })?;
            if !known_steps.contains(&next_action.as_str()) {
                return Err(Error::UnsupportedAuthStep { next_action });
            }
            Ok(Self::Challenge {
                token: token.into(),
                next_action,
            })
        }
    }
}

impl fmt::Debug for TokenStep {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(match self {
            Self::Complete { .. } => "TokenStep::Complete { [REDACTED] }",
            Self::Challenge { .. } => "TokenStep::Challenge { [REDACTED] }",
        })
    }
}
