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
const bytes = rate * 50 * 2;
const mix = Buffer.alloc(bytes + header.length);
header.copy(mix);
mix.writeUInt32LE(mix.length - 8, 4);
mix.writeUInt32LE(bytes, 40);
for (let i = 44; i < mix.length; i += 2) {
  let sample = tracks.reduce((sum, { pcm, gain }) => sum + pcm.readInt16LE(i) * gain, 0);
  const frame = (i - 44) / 2;
  const afterUpbeat = frame % samplesPerBeat - halfBeat;
  if (frame >= rate * 2 && afterUpbeat >= 0 && afterUpbeat < rate * 0.056) {
    sample += guide.readInt16LE(44 + (samplesPerBeat + afterUpbeat) * 2) * 0.29;
  }
  const fade = Math.min(1, (mix.length - i) / (rate * 0.04));
  const value = Math.round(sample * fade);
  if (Math.abs(value) >= 32767) throw new Error('Clipping in the music mix');
  mix.writeInt16LE(value, i);
}
fs.writeFileSync(path.join(directory, 'rhythm_mix.wav'), mix);
