use serde_json::Value;

use crate::runtime::{
    Association, Error, InputValue, JsonMap, ParameterKind, ParameterSpec, ValidationErrors,
};

/// Validation must precede Serde conversion, which would turn nonfinite floats into null.
pub trait Validate {
    fn validate(&self) -> Result<(), Error>;
}

impl<T: Validate> Validate for InputValue<T> {
    fn validate(&self) -> Result<(), Error> {
        match self {
            Self::Value(value) => value.validate(),
            _ => Ok(()),
        }
    }
}

impl<T: Validate> Validate for Vec<T> {
    fn validate(&self) -> Result<(), Error> {
        self.iter().try_for_each(Validate::validate)
    }
}

impl Validate for f64 {
    fn validate(&self) -> Result<(), Error> {
        if self.is_finite() {
            Ok(())
        } else {
            Err(Error::validation("input", "not a valid finite float"))
        }
    }
}

macro_rules! valid_types {
    ($($ty:ty),*) => { $(impl Validate for $ty { fn validate(&self) -> Result<(), Error> { Ok(()) } })* };
}
valid_types!((), String, i64, bool, Value, Association);

pub(crate) fn validate_map(
    map: &JsonMap,
    specs: &[ParameterSpec],
    prefix: &str,
) -> Result<(), Error> {
    let mut errors = ValidationErrors::new();
    for spec in specs {
        let problem = match map.get(spec.name) {
            None if spec.required => Some("is required"),
            None => None,
            Some(Value::Null) if !spec.nullable || spec.required => Some("cannot be null"),
            Some(Value::Null) => None,
            Some(value) => validate_kind(value, spec.kind),
        };
        if let Some(message) = problem {
            errors.insert(format!("{prefix}{}", spec.name), vec![message.to_owned()]);
        }
    }
    for name in map.keys() {
        if !specs.iter().any(|spec| spec.name == name) {
            errors.insert(
                format!("{prefix}{name}"),
                vec!["is not a described parameter".to_owned()],
            );
        }
    }
    if errors.is_empty() {
        Ok(())
    } else {
        Err(Error::Validation { errors })
    }
}

fn validate_kind(value: &Value, kind: ParameterKind) -> Option<&'static str> {
    let (valid, message) = match kind {
        ParameterKind::String | ParameterKind::Text => (value.is_string(), "not a valid string"),
        ParameterKind::Integer => (value.as_i64().is_some(), "not a valid integer"),
        ParameterKind::Float => (
            value.as_f64().is_some_and(f64::is_finite),
            "not a valid finite float",
        ),
        ParameterKind::Boolean => (value.is_boolean(), "not a valid boolean"),
        ParameterKind::Datetime => (
            value.as_str().is_some_and(valid_datetime),
            "not in ISO 8601 format",
        ),
        ParameterKind::Resource => (
            value.as_i64().is_some_and(|id| id >= 0),
            "not a valid resource ID",
        ),
        ParameterKind::Custom => (true, ""),
    };
    if valid { None } else { Some(message) }
}

// Match the documented HaveAPI wire grammar, including date-only values and
// shortened times. A pure RFC3339 parser would reject supported values.
fn valid_datetime(value: &str) -> bool {
    let bytes = value.as_bytes();
    if bytes.len() < 10 || bytes[4] != b'-' || bytes[7] != b'-' {
        return false;
    }
    let (Some(year), Some(month), Some(day)) = (
        digits(&bytes[0..4]),
        digits(&bytes[5..7]),
        digits(&bytes[8..10]),
    ) else {
        return false;
    };
    let leap = year.is_multiple_of(4) && (!year.is_multiple_of(100) || year.is_multiple_of(400));
    let days = match month {
        1 | 3 | 5 | 7 | 8 | 10 | 12 => 31,
        4 | 6 | 9 | 11 => 30,
        2 if leap => 29,
        2 => 28,
        _ => return false,
    };
    if year == 0 || day == 0 || day > days {
        return false;
    }
    if bytes.len() == 10 {
        return true;
    }
    if bytes.len() < 17 || bytes[10] != b'T' || bytes[13] != b':' {
        return false;
    }
    if !digits(&bytes[11..13]).is_some_and(|hour| hour <= 23)
        || !digits(&bytes[14..16]).is_some_and(|minute| minute <= 59)
    {
        return false;
    }
    let mut cursor = 16;
    if bytes.get(cursor) == Some(&b':') {
        if bytes.len() < cursor + 3
            || !digits(&bytes[cursor + 1..cursor + 3]).is_some_and(|second| second <= 59)
        {
            return false;
        }
        cursor += 3;
        if bytes.get(cursor) == Some(&b'.') {
            cursor += 1;
            let start = cursor;
            while bytes.get(cursor).is_some_and(u8::is_ascii_digit) {
                cursor += 1;
            }
            if cursor == start {
                return false;
            }
        }
    }
    let zone = &bytes[cursor..];
    if zone == b"Z" {
        return true;
    }
    if !matches!(zone.first(), Some(b'+' | b'-')) {
        return false;
    }
    let (hour, minute) = match zone.len() {
        5 => (digits(&zone[1..3]), digits(&zone[3..5])),
        6 if zone[3] == b':' => (digits(&zone[1..3]), digits(&zone[4..6])),
        _ => return false,
    };
    hour.is_some_and(|hour| hour <= 23) && minute.is_some_and(|minute| minute <= 59)
}

fn digits(bytes: &[u8]) -> Option<u32> {
    bytes.iter().try_fold(0, |acc, digit| {
        if digit.is_ascii_digit() {
            Some(acc * 10 + u32::from(digit - b'0'))
        } else {
            None
        }
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn datetime_grammar_and_calendar() {
        for value in [
            "2020-02-29",
            "2020-01-31T10:20Z",
            "2020-01-31T10:20+01:30",
            "2020-01-31T10:20:30.123-0500",
            "2000-02-29T23:59:59Z",
        ] {
            assert!(valid_datetime(value), "{value}");
        }
        for value in [
            "",
            "2020/01/31",
            "1900-02-29",
            "2020-02-30",
            "0000-01-01",
            "2020-00-01",
            "2020-01-00",
            "2020-01-31T10:20",
            "2020-01-31T24:00Z",
            "2020-01-31T10:60Z",
            "2020-01-31T10:20:60Z",
            "2020-01-31T10:20:30.Z",
            "2020-01-31T10:20+2400",
            "2020-01-31T10:20+0060",
            "2020-01-31T10:20Zx",
            "２０２０-01-31",
        ] {
            assert!(!valid_datetime(value), "{value}");
        }
    }
}
