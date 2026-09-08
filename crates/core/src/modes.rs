//! Session-only action layers; never persisted or transferred between physical watches.
use crate::model::{ActionsConfig, WatchAction, WatchButtonEvent};
use std::collections::BTreeSet;

#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub enum ActionLayer {
    #[default]
    Normal,
    Alternate,
}
impl ActionLayer {
    pub fn title(self) -> &'static str {
        match self {
            Self::Normal => "Normal",
            Self::Alternate => "Alternate",
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
    alternate: BTreeSet<String>,
}
impl ActionModes {
    pub fn layer(&self, id: &str) -> ActionLayer {
        if self.alternate.contains(id) {
            ActionLayer::Alternate
        } else {
            ActionLayer::Normal
        }
    }
    pub fn reset(&mut self) {
        self.alternate.clear();
    }
    pub fn forget(&mut self, id: &str) {
        self.alternate.remove(id);
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
            if !self.alternate.remove(id) {
                if self.alternate.len() >= 100 {
                    return ActionResolution::Ignored;
                }
                self.alternate.insert(id.to_owned());
            }
            return ActionResolution::Switched(self.layer(id));
        }
        ActionResolution::Action(config.action_in_layer(event, self.layer(id)))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::ActionKind;
    #[test]
    fn old_configuration_keeps_actions_and_new_fields_round_trip() {
        let config = ActionsConfig::default();
        let mut old = serde_json::to_value(&config).unwrap();
        old.as_object_mut().unwrap().remove("alternate_actions");
        old.as_object_mut().unwrap().remove("switch_event");
        for action in old["actions"].as_object_mut().unwrap().values_mut() {
            action.as_object_mut().unwrap().remove("keyboard");
        }
        let restored: ActionsConfig = serde_json::from_value(old).unwrap();
        assert_eq!(restored, config);
        let mut updated = config;
        updated.switch_event = Some(WatchButtonEvent::Find);
        updated.alternate_actions.insert(
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
        config.alternate_actions.insert(
            WatchButtonEvent::Automatic,
            WatchAction::new(ActionKind::Keyboard),
        );
        assert_eq!(
            config.action_in_layer(WatchButtonEvent::Automatic, ActionLayer::Alternate),
            config.action(WatchButtonEvent::Automatic)
        );
    }
    #[test]
    fn invalid_keyboard_payload_is_disabled_during_normalization() {
        let mut data = crate::model::AppData::default();
        let mut action = WatchAction::new(ActionKind::Keyboard);
        action.keyboard.as_mut().unwrap().repetitions = 0;
        data.actions
            .alternate_actions
            .insert(WatchButtonEvent::Time, action);
        data.trim_for_storage();
        assert_eq!(
            data.actions
                .action_in_layer(WatchButtonEvent::Time, ActionLayer::Alternate),
            WatchAction::default()
        );
    }
    #[test]
    fn layers_are_isolated_and_the_switch_always_returns_home() {
        let mut config = ActionsConfig {
            switch_event: Some(WatchButtonEvent::Find),
            ..Default::default()
        };
        config.alternate_actions.insert(
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
            ActionResolution::Switched(ActionLayer::Alternate)
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
