use std::fmt;

use crate::runtime::ValidationErrors;

/// Failures never include raw request/response values in Display or Debug.
#[non_exhaustive]
pub enum Error {
    Configuration {
        reason: &'static str,
    },
    Validation {
        errors: ValidationErrors,
    },
    Encode,
    Transport {
        timeout: bool,
    },
    Http {
        status: u16,
    },
    Api {
        status: u16,
        message: Option<String>,
        errors: ValidationErrors,
    },
    Protocol {
        status: Option<u16>,
        reason: &'static str,
    },
    Decode {
        status: u16,
    },
    ResponseTooLarge {
        limit: usize,
    },
    UnsupportedAuthStep {
        next_action: String,
    },
}

impl Error {
    pub fn validation(name: impl Into<String>, message: impl Into<String>) -> Self {
        let mut errors = ValidationErrors::new();
        errors.insert(name.into(), vec![message.into()]);
        Self::Validation { errors }
    }

    pub fn http_status(&self) -> Option<u16> {
        match self {
            Self::Http { status } | Self::Api { status, .. } | Self::Decode { status } => {
                Some(*status)
            }
            Self::Protocol { status, .. } => *status,
            _ => None,
        }
    }

    /// Explicit diagnostic access; server messages can contain sensitive values.
    pub fn server_message(&self) -> Option<&str> {
        match self {
            Self::Api { message, .. } => message.as_deref(),
            _ => None,
        }
    }

    /// Explicit diagnostic access; validation details can contain sensitive values.
    pub fn validation_errors(&self) -> Option<&ValidationErrors> {
        match self {
            Self::Validation { errors } | Self::Api { errors, .. } => Some(errors),
            _ => None,
        }
    }

    pub fn is_timeout(&self) -> bool {
        matches!(self, Self::Transport { timeout: true })
    }

    pub fn unsupported_auth_step(&self) -> Option<&str> {
        match self {
            Self::UnsupportedAuthStep { next_action } => Some(next_action),
            _ => None,
        }
    }

    pub(crate) fn configuration(reason: &'static str) -> Self {
        Self::Configuration { reason }
    }

    pub(crate) fn protocol(status: Option<u16>, reason: &'static str) -> Self {
        Self::Protocol { status, reason }
    }

    pub(crate) fn transport(error: reqwest::Error) -> Self {
        Self::Transport {
            timeout: error.is_timeout(),
        }
    }
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Configuration { reason } => write!(f, "invalid client configuration: {reason}"),
            Self::Validation { .. } => f.write_str("input validation failed"),
            Self::Encode => f.write_str("request encoding failed"),
            Self::Transport { timeout: true } => {
                f.write_str("HTTP request timed out; execution may have occurred")
            }
            Self::Transport { timeout: false } => {
                f.write_str("HTTP transport failed; execution may have occurred")
            }
            Self::Http { status } => write!(f, "HTTP request failed with status {status}"),
            Self::Api { status, .. } => {
                write!(f, "HaveAPI action failed with HTTP status {status}")
            }
            Self::Protocol { reason, .. } => write!(f, "invalid HaveAPI response: {reason}"),
            Self::Decode { .. } => f.write_str("HaveAPI response has incompatible field types"),
            Self::ResponseTooLarge { limit } => {
                write!(f, "HTTP response exceeds the {limit} byte limit")
            }
            Self::UnsupportedAuthStep { .. } => {
                f.write_str("unsupported authentication continuation step")
            }
        }
    }
}

impl fmt::Debug for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        fmt::Display::fmt(self, f)
    }
}

impl std::error::Error for Error {}
