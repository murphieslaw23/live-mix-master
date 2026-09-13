abstract interface class NativeAudioGainBindings {
  bool setTrim(String channelId, double db);
  bool setMasterGain(double db);
}
