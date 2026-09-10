#include "dsp_kernel.hpp"

#include <cmath>
#include <cstddef>
#include <fstream>
#include <iostream>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

namespace {

struct FixtureChannel {
  std::string id;
  float linearTrim = 1.0F;
  float fader = 0.8F;
  bool muted = false;
  bool solo = false;
  std::vector<float> interleaved;
};

std::vector<std::string> split(const std::string& value, char delimiter) {
  std::vector<std::string> parts;
  std::stringstream stream(value);
  std::string part;
  while (std::getline(stream, part, delimiter)) {
    parts.push_back(part);
  }
  return parts;
}

std::vector<float> parseFloats(const std::string& value) {
  std::vector<float> values;
  for (const auto& token : split(value, ',')) {
    values.push_back(std::stof(token));
  }
  return values;
}

bool closeEnough(float actual, float expected) {
  return std::fabs(actual - expected) <= 1.0e-6F;
}

void require(bool condition, const std::string& message) {
  if (!condition) {
    throw std::runtime_error(message);
  }
}

void runCase(const std::vector<std::string>& fields) {
  require(fields.size() == 7, "fixture row must contain 7 tab-separated fields");

  const std::string& name = fields[0];
  const float masterGain = std::stof(fields[1]);
  const auto channelSpecs = split(fields[2], '|');
  const auto expectedOutput = parseFloats(fields[3]);
  const bool expectedLimiter = fields[4] == "1";
  const float expectedPeakLeft = std::stof(fields[5]);
  const float expectedPeakRight = std::stof(fields[6]);

  require(!channelSpecs.empty(), name + ": requires at least one channel");
  require(expectedOutput.size() % 2 == 0, name + ": expected stereo output must be interleaved");
  const std::size_t frames = expectedOutput.size() / 2;

  std::vector<FixtureChannel> fixtureChannels;
  fixtureChannels.reserve(channelSpecs.size());
  for (const auto& spec : channelSpecs) {
    const auto parts = split(spec, ';');
    require(parts.size() == 6, name + ": channel spec must contain 6 semicolon-separated fields");

    FixtureChannel channel;
    channel.id = parts[0];
    channel.linearTrim = std::stof(parts[1]);
    channel.fader = std::stof(parts[2]);
    channel.muted = parts[3] == "1";
    channel.solo = parts[4] == "1";
    channel.interleaved = parseFloats(parts[5]);
    require(channel.interleaved.size() == expectedOutput.size(), name + ": channel frame count mismatch");
    fixtureChannels.push_back(std::move(channel));
  }

  std::vector<lmm::DspChannelConfig> configs;
  std::vector<const float*> inputs;
  std::vector<lmm::DspChannelMeter> meters(fixtureChannels.size());
  configs.reserve(fixtureChannels.size());
  inputs.reserve(fixtureChannels.size());

  for (const auto& channel : fixtureChannels) {
    configs.push_back(lmm::DspChannelConfig{
        true,
        channel.muted,
        channel.solo,
        channel.linearTrim,
        channel.fader,
    });
    inputs.push_back(channel.interleaved.data());
  }

  std::vector<float> output(expectedOutput.size(), 0.0F);
  const auto master = lmm::processStereoBlock(
      configs.data(),
      inputs.data(),
      configs.size(),
      output.data(),
      frames,
      masterGain,
      meters.data());

  for (std::size_t index = 0; index < expectedOutput.size(); ++index) {
    require(
        closeEnough(output[index], expectedOutput[index]),
        name + ": output mismatch at sample " + std::to_string(index));
  }
  require(master.limiterActive == expectedLimiter, name + ": limiter state mismatch");
  require(closeEnough(master.peakLeft, expectedPeakLeft), name + ": master left peak mismatch");
  require(closeEnough(master.peakRight, expectedPeakRight), name + ": master right peak mismatch");
}

}  // namespace

int main(int argc, char** argv) {
  if (argc != 2) {
    std::cerr << "usage: dsp_parity_vectors_test <fixture.tsv>\n";
    return 2;
  }

  std::ifstream input(argv[1]);
  if (!input) {
    std::cerr << "cannot open fixture: " << argv[1] << '\n';
    return 2;
  }

  try {
    std::string line;
    std::size_t executed = 0;
    while (std::getline(input, line)) {
      if (line.empty() || line.front() == '#') {
        continue;
      }
      runCase(split(line, '\t'));
      ++executed;
    }
    require(executed >= 4, "expected at least four DSP parity cases");
    std::cout << "DSP parity vectors passed: " << executed << '\n';
  } catch (const std::exception& error) {
    std::cerr << error.what() << '\n';
    return 1;
  }

  return 0;
}
