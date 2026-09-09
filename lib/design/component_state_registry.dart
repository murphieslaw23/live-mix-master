/// Repository-owned executable mirror of `design/component-states.json`.
///
/// The strings are intentionally kept identical to the JSON contract so tests
/// can detect accidental vocabulary drift without adding a runtime JSON parser.
abstract final class LiveMixComponentStateRegistry {
  static const Map<String, Set<String>> statesByComponent = {
    'channelStrip': {
      'default',
      'active',
      'muted',
      'solo',
      'disabled',
      'disconnected',
      'clipping',
    },
    'trimKnob': {'default', 'hover', 'focus', 'disabled'},
    'fader': {'default', 'active', 'focus', 'disabled'},
    'muteControl': {'off', 'on', 'focus', 'disabled'},
    'soloControl': {'off', 'on', 'focus', 'disabled'},
    'stereoMeter': {'inactive', 'nominal', 'headroom', 'clipping'},
    'masterBus': {'default', 'limiterOn', 'clipping'},
    'recordControl': {
      'idle',
      'recording',
      'finalizing',
      'finalized',
      'writeFailure',
      'diskFull',
    },
    'broadcastControl': {
      'offline',
      'preflight',
      'live',
      'reconnecting',
      'failed',
      'invalidCredentials',
    },
    'fingerprintHud': {
      'searching',
      'match',
      'lowConfidence',
      'noMatch',
      'offlineLookup',
    },
    'sessionRow': {
      'approved',
      'candidate',
      'needsReview',
      'ignored',
      'disabled',
    },
    'deviceStatus': {
      'connected',
      'active',
      'muted',
      'noSignal',
      'lost',
      'permissionDenied',
      'notDetected',
      'recovered',
    },
    'preflightCheck': {'ok', 'warning', 'error', 'disabled'},
  };
}
