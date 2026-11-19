'use strict';
// Independent, phase-locked beat guide. Existing music is read only.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const ROOT = path.resolve(__dirname, '..');
const OUT = path.join(ROOT, 'assets', 'audio', 'wreck3d');
const RATE = 22050, SECONDS = 52, FRAMES = RATE * SECONDS;
const TAU = Math.PI * 2;
const data = new Float64Array(FRAMES);
const events = [];

// 0..1.5 seconds: four preparation taps; 2..49.5: 96 battle beats.
// The first note of each bar is higher, with a slightly brighter wood attack.
for (let index = 0; index < 100; index++) {
  const time = index * 0.5, start = Math.round(time * RATE);
  const accent = index % 4 === 0;
  const frequency = accent ? 1120 : 790;
  const length = accent ? 0.064 : 0.056;
  const count = Math.ceil(length * RATE);
  for (let i = 0; i < count; i++) {
    const t = i / RATE;
    const onset = Math.min(1, t / 0.00018);
    const tail = Math.max(0, Math.min(1, (length - t) / 0.007));
    const wood = (Math.sin(TAU * frequency * t) + Math.sin(TAU * frequency * 1.73 * t) * 0.18) * Math.exp(-t * (accent ? 88 : 102));
    const low = Math.sin(TAU * (accent ? 238 : 185) * t) * Math.exp(-t * 68) * 0.36;
    const click = Math.sin(TAU * (accent ? 1960 : 1510) * t) * Math.exp(-t * 230) * (accent ? 0.18 : 0.10);
    data[start + i] += (wood + low + click) * (accent ? 0.17 : 0.145) * onset * tail;
  }
  events.push({ index, time, frame: start, accent, battle_beat: index - 4, section: index < 4 ? 'count_in' : 'battle' });
}

const b = Buffer.alloc(44 + FRAMES * 2);
b.write('RIFF', 0); b.writeUInt32LE(b.length - 8, 4); b.write('WAVE', 8);
b.write('fmt ', 12); b.writeUInt32LE(16, 16); b.writeUInt16LE(1, 20); b.writeUInt16LE(1, 22);
b.writeUInt32LE(RATE, 24); b.writeUInt32LE(RATE * 2, 28); b.writeUInt16LE(2, 32); b.writeUInt16LE(16, 34);
b.write('data', 36); b.writeUInt32LE(FRAMES * 2, 40);
let lastIn = 0, lastOut = 0;
const highpass = Math.exp(-TAU * 35 / RATE);
for (let i = 0; i < FRAMES; i++) {
  const filtered = highpass * (lastOut + data[i] - lastIn);
  lastIn = data[i]; lastOut = filtered;
  b.writeInt16LE(Math.round(filtered * 32767), 44 + i * 2);
}
fs.mkdirSync(OUT, { recursive: true });
fs.writeFileSync(path.join(OUT, 'guide.wav'), b);

// Re-open actual guide PCM, check every event onset and inspect actual music mix.
const actual = fs.readFileSync(path.join(OUT, 'guide.wav'));
const existingNames = ['bed.wav', 'response_even.wav', 'response_odd.wav'];
const existing = existingNames.map(name => fs.readFileSync(path.join(OUT, name)));
let peak = 0, squares = 0, clipped = 0, dc = 0, mixedPeak = 0;
const guideGain = 10 ** (-3 / 20), bedGain = 10 ** (-4 / 20), responseGain = 10 ** (-1 / 20);
for (let i = 0; i < FRAMES; i++) {
  const pcm = actual.readInt16LE(44 + i * 2), sample = pcm / 32768;
  peak = Math.max(peak, Math.abs(sample)); squares += sample ** 2; dc += sample;
  if (Math.abs(pcm) >= 32767) clipped++;
  const mix = existing[0].readInt16LE(44 + i * 2) / 32768 * bedGain + (existing[1].readInt16LE(44 + i * 2) + existing[2].readInt16LE(44 + i * 2)) / 32768 * responseGain + sample * guideGain;
  mixedPeak = Math.max(mixedPeak, Math.abs(mix));
}
let firstOnset = Infinity, largestOnset = 0, checks = 0;
for (const event of events) {
  let onset = -1;
  for (let i = 0; i < 23; i++) if (Math.abs(actual.readInt16LE(44 + (event.frame + i) * 2)) > 32) { onset = i; break; }
  if (onset < 0 || event.frame !== event.time * RATE) throw Error('Misaligned or slow beat ' + event.index);
  firstOnset = Math.min(firstOnset, onset); largestOnset = Math.max(largestOnset, onset);
  checks++;
}
if (actual.readUInt32LE(24) !== RATE || actual.readUInt16LE(22) !== 1 || actual.readUInt16LE(34) !== 16 || actual.readUInt32LE(40) !== FRAMES * 2 || clipped || peak >= 0.3 || mixedPeak >= 0.9) throw Error('Guide/mix PCM validation');
checks += 5;
const metadata = {
  file: 'guide.wav', bpm: 120, sample_rate: RATE, bit_depth: 16, channels: 1, frames: FRAMES, duration: SECONDS, bytes: actual.length,
  prepare_taps: 4, battle_taps: 96, total_taps: 100, final_tap: 49.5, first_onset_frames: firstOnset, largest_onset_frames: largestOnset,
  peak: +peak.toFixed(6), rms: +Math.sqrt(squares / FRAMES).toFixed(6), dc_mean: +(dc / FRAMES).toFixed(9), clipped_samples: clipped,
  recommended_volume_db: -3,
  mix_recommendation: 'guide -3dB, bed -4dB, each response -1dB. Start guide, bed and both response stems together from 0; pause/resume/stop all four together. Do not loop the 52s file. The guide is a quiet short woodblock/low knock, first beat of every bar brighter. Halfbeat response melody stays unchanged.',
  validation: { checks, passed: true, actual_bed_plus_all_responses_plus_guide_peak: +mixedPeak.toFixed(6), existing_music_sha256: Object.fromEntries(existing.map((buffer, i) => [existingNames[i], crypto.createHash('sha256').update(buffer).digest('hex')])) }, events
};
fs.writeFileSync(path.join(OUT, 'guide-metadata.json'), JSON.stringify(metadata, null, 2) + '\n');
console.log(JSON.stringify({ ...metadata, events: undefined }, null, 2));
