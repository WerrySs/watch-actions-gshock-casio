use chrono::{DateTime, Datelike, Local, NaiveDate, Timelike};

use crate::model::{Alarm, Reminder, RepeatMode, WatchButtonEvent, WatchSettings, Weekday};

pub mod code {
    pub const CURRENT_TIME: u8 = 0x09;
    pub const BLE_FEATURES: u8 = 0x10;
    pub const TIME_ADJUSTMENT: u8 = 0x11;
    pub const BASIC_SETTINGS: u8 = 0x13;
    pub const ALARM_1: u8 = 0x15;
    pub const ALARMS_2_TO_5: u8 = 0x16;
    pub const TIMER: u8 = 0x18;
    pub const DST_WATCH_STATE: u8 = 0x1D;
    pub const DST_SETTING: u8 = 0x1E;
    pub const WORLD_CITIES: u8 = 0x1F;
    pub const APP_INFO: u8 = 0x22;
    pub const WATCH_NAME: u8 = 0x23;
    pub const CONDITION: u8 = 0x28;
    pub const REMINDER_TITLE: u8 = 0x30;
    pub const REMINDER_TIME: u8 = 0x31;
}

pub const APP_INFO_RESPONSE: [u8; 12] = [
    0x22, 0x34, 0x88, 0xF4, 0xE5, 0xD5, 0xAF, 0xC8, 0x29, 0xE0, 0x6D, 0x02,
];

pub fn decode_button(data: &[u8]) -> WatchButtonEvent {
    if data.len() < 19 || data[0] != code::BLE_FEATURES {
        return WatchButtonEvent::Unknown;
    }
    match data[8] {
        0 | 1 => WatchButtonEvent::Connect,
        2 => WatchButtonEvent::Find,
        3 => WatchButtonEvent::Automatic,
        4 => WatchButtonEvent::Time,
        _ => WatchButtonEvent::Unknown,
    }
}

pub fn is_app_info_challenge(data: &[u8]) -> bool {
    data.len() >= 12
        && data[0] == code::APP_INFO
        && data[1..=10].iter().all(|byte| *byte == 0xFF)
        && data[11] == 0
}

pub fn decode_name(data: &[u8]) -> String {
    ascii(data.get(1..).unwrap_or_default())
}

pub fn decode_condition(data: &[u8]) -> Option<(u8, i16)> {
    if data.len() < 3 || data[0] != code::CONDITION {
        return None;
    }
    let battery = i16::from(data[1])
        .saturating_sub(9)
        .saturating_mul(10)
        .clamp(0, 100);
    Some((battery as u8, i16::from(data[2])))
}

pub fn decode_city(data: &[u8]) -> String {
    ascii(data.get(2..).unwrap_or_default())
}

pub fn encode_time(date: DateTime<Local>) -> Vec<u8> {
    let year = date.year().clamp(0, i32::from(u16::MAX)) as u16;
    let fractional = ((u64::from(date.nanosecond()) * 256) / 1_000_000_000) as u8;
    vec![
        code::CURRENT_TIME,
        (year & 0xFF) as u8,
        (year >> 8) as u8,
        date.month() as u8,
        date.day() as u8,
        date.hour() as u8,
        date.minute() as u8,
        date.second() as u8,
        date.weekday().num_days_from_monday() as u8,
        fractional,
        0x01,
    ]
}

pub fn decode_automatic_time_adjustment(data: &[u8]) -> Option<bool> {
    (data.len() >= 14 && data[0] == code::TIME_ADJUSTMENT).then(|| data[12] == 0)
}

pub fn encode_automatic_time_adjustment(
    original: &[u8],
    enabled: bool,
    minutes_after_hour: u8,
) -> Vec<u8> {
    let mut output = original.to_vec();
    if output.len() >= 14 {
        output[12] = if enabled { 0 } else { 0x80 };
        output[13] = minutes_after_hour.min(59);
    }
    output
}

pub fn decode_alarms(first: &[u8], rest: &[u8]) -> Option<Vec<Alarm>> {
    if first.len() < 5
        || first[0] != code::ALARM_1
        || rest.len() < 17
        || rest[0] != code::ALARMS_2_TO_5
    {
        return None;
    }

    fn alarm(number: u8, bytes: &[u8]) -> Alarm {
        Alarm {
            number,
            hour: bytes[2].min(23),
            minute: bytes[3].min(59),
            enabled: bytes[0] & 0x40 != 0,
            hourly_chime: bytes[0] & 0x80 != 0,
        }
    }

    let mut alarms = vec![alarm(1, &first[1..5])];
    for index in 0..4 {
        let start = 1 + index * 4;
        alarms.push(alarm((index + 2) as u8, &rest[start..start + 4]));
    }
    Some(alarms)
}

pub fn encode_alarms(alarms: &[Alarm]) -> Option<(Vec<u8>, Vec<u8>)> {
    if alarms.len() != 5 {
        return None;
    }
    let mut sorted = alarms.to_vec();
    sorted.sort_by_key(|alarm| alarm.number);
    let flag = |alarm: &Alarm| {
        (if alarm.enabled { 0x40 } else { 0 }) | (if alarm.hourly_chime { 0x80 } else { 0 })
    };
    let first_alarm = &sorted[0];
    let first = vec![
        code::ALARM_1,
        flag(first_alarm),
        0x40,
        first_alarm.hour.min(23),
        first_alarm.minute.min(59),
    ];
    let mut rest = vec![code::ALARMS_2_TO_5];
    for alarm in sorted.iter().skip(1) {
        rest.extend_from_slice(&[flag(alarm), 0x40, alarm.hour.min(23), alarm.minute.min(59)]);
    }
    Some((first, rest))
}

pub fn decode_timer(data: &[u8]) -> Option<u32> {
    (data.len() >= 4 && data[0] == code::TIMER)
        .then(|| u32::from(data[1]) * 3_600 + u32::from(data[2]) * 60 + u32::from(data[3]))
}

pub fn encode_timer(seconds: u32) -> Vec<u8> {
    let seconds = seconds.min(23 * 3_600 + 59 * 60 + 59);
    vec![
        code::TIMER,
        (seconds / 3_600) as u8,
        ((seconds % 3_600) / 60) as u8,
        (seconds % 60) as u8,
        0,
        0,
    ]
}

pub fn decode_settings(data: &[u8]) -> Option<WatchSettings> {
    if data.len() < 6 || data[0] != code::BASIC_SETTINGS {
        return None;
    }
    Some(WatchSettings {
        twenty_four_hour: data[1] & 0x01 != 0,
        button_tone: data[1] & 0x02 == 0,
        automatic_light: data[1] & 0x04 == 0,
        power_saving: data[1] & 0x10 == 0,
        long_light: data[2] == 1,
        day_first_date: data[4] == 1,
        language_index: data[5].min((WatchSettings::LANGUAGES.len() - 1) as u8),
    })
}

pub fn encode_settings(settings: &WatchSettings) -> Vec<u8> {
    let mut output = vec![0_u8; 12];
    output[0] = code::BASIC_SETTINGS;
    if settings.twenty_four_hour {
        output[1] |= 0x01;
    }
    if !settings.button_tone {
        output[1] |= 0x02;
    }
    if !settings.automatic_light {
        output[1] |= 0x04;
    }
    if !settings.power_saving {
        output[1] |= 0x10;
    }
    output[2] = u8::from(settings.long_light);
    output[4] = u8::from(settings.day_first_date);
    output[5] = settings
        .language_index
        .min((WatchSettings::LANGUAGES.len() - 1) as u8);
    output
}

pub fn encode_reminder_title(reminder: &Reminder) -> Vec<u8> {
    let mut title = reminder.watch_title().into_bytes();
    title.resize(18, 0);
    let mut packet = vec![code::REMINDER_TITLE, reminder.slot.clamp(1, 5)];
    packet.extend(title);
    packet
}

pub fn encode_reminder_time(reminder: &Reminder) -> Vec<u8> {
    let mut period = u8::from(reminder.enabled) | reminder.repeat_mode.mask();
    if !reminder.enabled {
        period &= !0x01;
    }
    let end = reminder.end.max(reminder.start);
    let day_mask = if reminder.repeat_mode == RepeatMode::Weekly {
        reminder.days.iter().fold(0, |mask, day| mask | day.mask())
    } else {
        0
    };
    vec![
        code::REMINDER_TIME,
        reminder.slot.clamp(1, 5),
        period,
        bcd((reminder.start.year() % 100) as u8),
        bcd(reminder.start.month() as u8),
        bcd(reminder.start.day() as u8),
        bcd((end.year() % 100) as u8),
        bcd(end.month() as u8),
        bcd(end.day() as u8),
        day_mask,
        0,
    ]
}

pub fn decode_reminder_title(data: &[u8]) -> Option<String> {
    if data.len() < 3 || data[0] != code::REMINDER_TITLE || data[2] == 0xFF {
        return None;
    }
    Some(ascii(&data[2..]))
}

pub fn decode_reminder_time(data: &[u8], reminder: &mut Reminder) -> bool {
    if data.len() < 10 || data[0] != code::REMINDER_TIME || data[3] == 0xFF {
        return false;
    }
    let period = data[2];
    reminder.enabled = period & 0x01 != 0;
    reminder.repeat_mode = if period & 0x04 != 0 {
        RepeatMode::Weekly
    } else if period & 0x10 != 0 {
        RepeatMode::Monthly
    } else if period & 0x08 != 0 {
        RepeatMode::Yearly
    } else {
        RepeatMode::Once
    };
    if let Some(start) = decode_date(&data[3..6]) {
        reminder.start = start;
    }
    reminder.end = decode_date(&data[6..9]).unwrap_or(reminder.start);
    reminder.days = Weekday::ALL
        .into_iter()
        .filter(|day| data[9] & day.mask() != 0)
        .collect();
    true
}

pub fn bcd(value: u8) -> u8 {
    ((value / 10) << 4) | (value % 10)
}

pub fn unbcd(value: u8) -> u8 {
    (value >> 4) * 10 + (value & 0x0F)
}

pub fn ascii(bytes: &[u8]) -> String {
    bytes
        .iter()
        .copied()
        .take_while(|byte| *byte != 0)
        .filter(|byte| (0x20..=0x7E).contains(byte))
        .map(char::from)
        .collect::<String>()
        .trim()
        .to_owned()
}

pub fn hex(bytes: &[u8]) -> String {
    bytes
        .iter()
        .map(|byte| format!("{byte:02X}"))
        .collect::<Vec<_>>()
        .join(" ")
}

fn decode_date(bytes: &[u8]) -> Option<NaiveDate> {
    if bytes.len() < 3 {
        return None;
    }
    NaiveDate::from_ymd_opt(
        2000 + i32::from(unbcd(bytes[0])),
        u32::from(unbcd(bytes[1])),
        u32::from(unbcd(bytes[2])),
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn decodes_the_four_supported_connection_reasons() {
        let mut packet = [0_u8; 19];
        packet[0] = code::BLE_FEATURES;
        for (value, event) in [
            (0, WatchButtonEvent::Connect),
            (2, WatchButtonEvent::Find),
            (3, WatchButtonEvent::Automatic),
            (4, WatchButtonEvent::Time),
        ] {
            packet[8] = value;
            assert_eq!(decode_button(&packet), event);
        }
        for value in 5..=255 {
            packet[8] = value;
            assert_eq!(decode_button(&packet), WatchButtonEvent::Unknown);
        }
        assert_eq!(decode_button(&packet[..18]), WatchButtonEvent::Unknown);
        packet[0] = 0xFF;
        assert_eq!(decode_button(&packet), WatchButtonEvent::Unknown);
    }

    #[test]
    fn condition_values_are_bounded() {
        assert_eq!(
            decode_condition(&[code::CONDITION, 19, 31]),
            Some((100, 31))
        );
        assert_eq!(decode_condition(&[code::CONDITION, 3, 20]), Some((0, 20)));
    }

    #[test]
    fn alarms_round_trip() {
        let alarms = vec![
            Alarm {
                number: 1,
                hour: 6,
                minute: 15,
                enabled: true,
                hourly_chime: true,
            },
            Alarm::new(2),
            Alarm::new(3),
            Alarm::new(4),
            Alarm::new(5),
        ];
        let (first, rest) = encode_alarms(&alarms).unwrap();
        assert_eq!(decode_alarms(&first, &rest).unwrap(), alarms);
    }

    #[test]
    fn application_challenge_is_exact() {
        let challenge = [
            0x22, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0,
        ];
        assert!(is_app_info_challenge(&challenge));
        assert!(!is_app_info_challenge(&[0x22, 0xFF, 0]));
    }
}
