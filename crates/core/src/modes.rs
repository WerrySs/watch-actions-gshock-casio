//! Session-only action layers; never persisted or transferred between physical watches.
use crate::model::{ActionsConfig, WatchAction, WatchButtonEvent};
use std::collections::BTreeMap;

#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub enum ActionLayer {
    #[default]
    Normal,
    Profile(u32),
}
impl ActionLayer {
    pub fn id(self) -> u32 {
        match self {
            Self::Normal => 0,
            Self::Profile(id) => id,
        }
    }
    pub fn from_id(id: u32) -> Self {
        if id == 0 {
            Self::Normal
        } else {
            Self::Profile(id)
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ActionResolution {
    Ignored,
    Switched(ActionLayer),
    Action(WatchAction),
}

#[derive(Debug, Default, Clone)]
pub struct ActionModes {
    active: BTreeMap<String, ActionLayer>,
}
impl ActionModes {
    pub fn layer(&self, id: &str) -> ActionLayer {
        self.active.get(id).copied().unwrap_or_default()
    }
    pub fn reset(&mut self) {
        self.active.clear();
    }
    pub fn forget(&mut self, id: &str) {
        self.active.remove(id);
    }
    pub fn resolve(
        &mut self,
        config: &ActionsConfig,
        id: &str,
        event: WatchButtonEvent,
        authorized: bool,
    ) -> ActionResolution {
        if !authorized
            || id.is_empty()
            || id.starts_with("manual-")
            || event == WatchButtonEvent::Unknown
        {
            return ActionResolution::Ignored;
        }
        if event != WatchButtonEvent::Automatic && config.switch_event == Some(event) {
            let next = config.next_layer(self.layer(id));
            if next == ActionLayer::Normal {
                self.active.remove(id);
            } else {
                if !self.active.contains_key(id) && self.active.len() >= 100 {
                    return ActionResolution::Ignored;
                }
                self.active.insert(id.to_owned(), next);
            }
            return ActionResolution::Switched(next);
        }
        ActionResolution::Action(config.action_in_layer(event, self.layer(id)))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::ActionKind;
    #[test]
    fn named_modes_cycle_in_order_without_crossing_watches_or_actions() {
        let mut config = ActionsConfig {
            switch_event: Some(WatchButtonEvent::Find),
            ..Default::default()
        };
        let music = config.add_profile("Music").unwrap();
        let slides = config.add_profile("Presentation").unwrap();
        config.actions_mut(music).unwrap().insert(
            WatchButtonEvent::Time,
            WatchAction::new(ActionKind::PlayPause),
        );
        let mut modes = ActionModes::default();
        for expected in [ActionLayer::Profile(1), music, slides, ActionLayer::Normal] {
            assert_eq!(
                modes.resolve(&config, "A", WatchButtonEvent::Find, true),
                ActionResolution::Switched(expected)
            );
            assert_eq!(modes.layer("B"), ActionLayer::Normal);
            assert_eq!(
                modes.resolve(&config, "A", WatchButtonEvent::Automatic, true),
                ActionResolution::Action(config.action(WatchButtonEvent::Automatic))
            );
        }
        config.profiles.swap(0, 2);
        assert_eq!(config.next_layer(ActionLayer::Normal), slides);
        assert_eq!(
            config.action_in_layer(WatchButtonEvent::Time, music).kind,
            ActionKind::PlayPause
        );
        config.profiles.retain(|p| p.id != music.id());
        assert!(config.actions_mut(music).is_none());
        assert_eq!(config.next_layer(music), ActionLayer::Normal);
        assert_eq!(
            config.action_in_layer(WatchButtonEvent::Time, music),
            WatchAction::default()
        );
    }
    #[test]
    fn legacy_alternate_migrates_with_its_actions_and_mode_limit_is_bounded() {
        let mut config = ActionsConfig::default();
        config.profiles[0].actions.insert(
            WatchButtonEvent::Time,
            WatchAction::new(ActionKind::PlayPause),
        );
        let mut old = serde_json::to_value(&config).unwrap();
        old["alternate_actions"] = old["profiles"][0]["actions"].clone();
        old.as_object_mut().unwrap().remove("profiles");
        let restored: ActionsConfig = serde_json::from_value(old).unwrap();
        assert_eq!(restored, config);
        for _ in 1..100 {
            assert!(config.add_profile("Mode").is_some());
        }
        assert!(config.add_profile("Too many").is_none());
    }
    #[test]
    fn old_configuration_keeps_actions_and_new_fields_round_trip() {
        let config = ActionsConfig::default();
        let mut old = serde_json::to_value(&config).unwrap();
        old.as_object_mut().unwrap().remove("alternate_actions");
        old.as_object_mut().unwrap().remove("profiles");
        old.as_object_mut().unwrap().remove("switch_event");
        for action in old["actions"].as_object_mut().unwrap().values_mut() {
            action.as_object_mut().unwrap().remove("keyboard");
        }
        let restored: ActionsConfig = serde_json::from_value(old).unwrap();
        assert_eq!(restored, config);
        let mut updated = config;
        updated.switch_event = Some(WatchButtonEvent::Find);
        updated.profiles[0].actions.insert(
            WatchButtonEvent::Time,
            WatchAction::new(ActionKind::Keyboard),
        );
        let encoded = serde_json::to_vec(&updated).unwrap();
        assert_eq!(
            serde_json::from_slice::<ActionsConfig>(&encoded).unwrap(),
            updated
        );
    }
    #[test]
    fn automatic_actions_ignore_the_alternate_configuration() {
        let mut config = ActionsConfig::default();
        config.profiles[0].actions.insert(
            WatchButtonEvent::Automatic,
            WatchAction::new(ActionKind::Keyboard),
        );
        assert_eq!(
            config.action_in_layer(WatchButtonEvent::Automatic, ActionLayer::Profile(1)),
            config.action(WatchButtonEvent::Automatic)
        );
    }
    #[test]
    fn invalid_keyboard_payload_is_disabled_during_normalization() {
        let mut data = crate::model::AppData::default();
        let mut action = WatchAction::new(ActionKind::Keyboard);
        action.keyboard.as_mut().unwrap().repetitions = 0;
        data.actions.profiles[0]
            .actions
            .insert(WatchButtonEvent::Time, action);
        data.trim_for_storage();
        assert_eq!(
            data.actions
                .action_in_layer(WatchButtonEvent::Time, ActionLayer::Profile(1)),
            WatchAction::default()
        );
    }
    #[test]
    fn layers_are_isolated_and_the_switch_always_returns_home() {
        let mut config = ActionsConfig {
            switch_event: Some(WatchButtonEvent::Find),
            ..Default::default()
        };
        config.profiles[0].actions.insert(
            WatchButtonEvent::Time,
            WatchAction::new(ActionKind::Keyboard),
        );
        let mut modes = ActionModes::default();
        assert_eq!(
            modes.resolve(&config, "A", WatchButtonEvent::Find, false),
            ActionResolution::Ignored
        );
        assert_eq!(
            modes.resolve(&config, "A", WatchButtonEvent::Find, true),
            ActionResolution::Switched(ActionLayer::Profile(1))
        );
        assert_eq!(modes.layer("B"), ActionLayer::Normal);
        assert_eq!(
            modes.resolve(&config, "A", WatchButtonEvent::Time, true),
            ActionResolution::Action(WatchAction::new(ActionKind::Keyboard))
        );
        assert_eq!(
            modes.resolve(&config, "A", WatchButtonEvent::Find, true),
            ActionResolution::Switched(ActionLayer::Normal)
        );
    }
    #[test]
    fn background_unknown_and_manual_events_never_switch() {
        let config = ActionsConfig {
            switch_event: Some(WatchButtonEvent::Automatic),
            ..Default::default()
        };
        let mut modes = ActionModes::default();
        modes.resolve(&config, "A", WatchButtonEvent::Automatic, true);
        modes.resolve(&config, "A", WatchButtonEvent::Unknown, true);
        modes.resolve(&config, "manual-A", WatchButtonEvent::Find, true);
        assert_eq!(modes.layer("A"), ActionLayer::Normal);
        assert_eq!(modes.layer("manual-A"), ActionLayer::Normal);
    }
    #[test]
    fn reset_and_revoke_remove_the_alternate_layer() {
        let config = ActionsConfig {
            switch_event: Some(WatchButtonEvent::Find),
            ..Default::default()
        };
        let mut modes = ActionModes::default();
        for id in ["A", "B"] {
            modes.resolve(&config, id, WatchButtonEvent::Find, true);
        }
        modes.forget("A");
        assert_eq!(modes.layer("A"), ActionLayer::Normal);
        modes.reset();
        assert_eq!(modes.layer("B"), ActionLayer::Normal);
    }
}
