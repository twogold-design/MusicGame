'use strict';

const fs = require('node:fs');
const path = require('node:path');

const directory = path.resolve(__dirname, '../assets/audio/wreck3d');
const tracks = [
  ['bed.wav', 0.82],
  ['response_even.wav', 0.52],
  ['response_odd.wav', 0.52],
  ['guide.wav', 0.94],
].map(([file, gain]) => ({ pcm: fs.readFileSync(path.join(directory, file)), gain }));

const header = tracks[0].pcm.subarray(0, 44);
for (const { pcm } of tracks) {
  if (!pcm.subarray(0, 44).equals(header)) throw new Error('The synchronized WAV tracks must have matching headers');
}
const rate = header.readUInt32LE(24);
const samplesPerBeat = rate / 2;
const halfBeat = Math.round(samplesPerBeat / 2);
const guide = tracks[3].pcm;
const upbeatGains = [0.24, 0.42, 0.17, 0.26, 0.44, 0.34];
const bytes = rate * 50 * 2;
const mix = Buffer.alloc(bytes + header.length);
header.copy(mix);
mix.writeUInt32LE(mix.length - 8, 4);
mix.writeUInt32LE(bytes, 40);
for (let i = 44; i < mix.length; i += 2) {
  const frame = (i - 44) / 2;
  const section = Math.max(0, Math.floor((frame - rate * 2) / (rate * 8)));
  const beat = Math.floor(frame / samplesPerBeat);
  const beatFrame = frame % samplesPerBeat;
  let sample = tracks.reduce((sum, { pcm, gain }, index) => {
    const thinner = section === 2 && index > 0 && index < 3;
    return sum + pcm.readInt16LE(i) * gain * (thinner ? 0.62 : 1);
  }, 0);
  const afterUpbeat = beatFrame - halfBeat;
  if (frame >= rate * 2 && afterUpbeat >= 0 && afterUpbeat < rate * 0.056) {
    const accent = beat % 2 === 0 ? 1.0 : 0.76;
    sample += guide.readInt16LE(44 + (samplesPerBeat + afterUpbeat) * 2) * upbeatGains[section] * accent;
  }
  const isDropBeat = (section === 3 && beat % 2 === 0) || (section === 5 && beat % 2 === 1);
  if (isDropBeat && beatFrame < rate * 0.115) {
    const t = beatFrame / rate;
    const envelope = Math.sin(Math.PI * t / 0.115) * Math.exp(-12 * t);
    sample += Math.sin(Math.PI * 2 * (78 * t - 100 * t * t)) * envelope * 4100;
  }
  const fade = Math.min(1, (mix.length - i) / (rate * 0.04));
  const value = Math.round(sample * fade);
  if (Math.abs(value) >= 32767) throw new Error('Clipping in the music mix');
  mix.writeInt16LE(value, i);
}
fs.writeFileSync(path.join(directory, 'rhythm_mix.wav'), mix);
