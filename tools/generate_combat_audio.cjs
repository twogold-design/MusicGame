'use strict';
// Original synth soundtrack: a 30-second, 120 BPM battle plus count-in and ending.
// Standard library only. No old audio files or game scripts are modified.
const fs = require('node:fs');
const path = require('node:path');
const ROOT = path.resolve(__dirname, '..');
const OUT = path.join(ROOT, 'assets', 'audio', 'combat');
const RATE = 22050, TAU = Math.PI * 2;
const hz = midi => 440 * 2 ** ((midi - 69) / 12);
let seed = 257183;
function noise() {
  seed ^= seed << 13; seed ^= seed >>> 17; seed ^= seed << 5;
  return (seed >>> 0) / 2147483648 - 1;
}
function renderer(seconds) {
  const data = new Float64Array(Math.round(seconds * RATE));
  function event(at, length, sample, attack = 0.002) {
    const start = Math.round(at * RATE), count = Math.ceil(length * RATE);
    for (let i = 0; i < count && start + i < data.length; i++) {
      if (start + i < 0) continue;
      const t = i / RATE;
      const edge = Math.max(0, Math.min(1, t / attack, (length - t) / 0.015));
      data[start + i] += sample(t) * edge;
    }
  }
  function note(midi, at, length, amp, voice = 'lead', echo = false) {
    const frequency = hz(midi);
    const sample = t => {
      const phase = TAU * frequency * t;
      let wave;
      if (voice === 'bass') wave = Math.sin(phase) * 0.86 + Math.sin(phase * 2) * 0.2 + Math.sin(phase * 3) * 0.06;
      else if (voice === 'pad') wave = Math.sin(phase) * 0.9 + Math.sin(phase * 2) * 0.08;
      else if (voice === 'bell') wave = Math.sin(phase + Math.sin(phase * 2) * 0.3 * Math.exp(-t * 15));
      else wave = Math.sin(phase) * 0.8 + Math.sin(phase * 2) * 0.17 + Math.sin(phase * 3) * 0.1 * Math.exp(-t * 12);
      return wave * Math.exp(-t / (length * (voice === 'pad' ? 0.75 : 0.34))) * amp;
    };
    event(at, length, sample, voice === 'pad' ? 0.04 : 0.005);
    if (echo) event(at + 0.375, length, t => sample(t) * 0.11);
  }
  function kick(at, amp = 0.43) {
    event(at, 0.29, t => {
      const phase = TAU * (52 * t + 105 / 38 * (1 - Math.exp(-38 * t)));
      return (Math.sin(phase) + Math.sin(phase * 2) * 0.21) * Math.exp(-t * 17) * amp;
    });
    // A short warm tap makes the quarter-note pulse legible on small speakers.
    event(at, 0.033, t => Math.sin(TAU * 1050 * t) * Math.exp(-t * 110) * 0.047);
  }
  function hat(at, strength = 1, open = false) {
    let previous = 0;
    const length = open ? 0.16 : 0.052;
    event(at, length, t => {
      const next = noise(), filtered = (next - previous * 0.78) * 0.55;
      previous = next;
      return filtered * Math.exp(-t / (length * 0.21)) * 0.052 * strength;
    });
  }
  function snare(at, strength = 1) {
    let previous = 0;
    event(at, 0.17, t => {
      const next = noise(), filtered = next - previous * 0.38;
      previous = next;
      return (filtered * Math.exp(-t * 31) * 0.12 + Math.sin(TAU * 190 * t) * Math.exp(-t * 45) * 0.075) * strength;
    });
  }
  return { data, event, note, kick, hat, snare };
}

function encode(data, gain = 1) {
  const buffer = Buffer.alloc(44 + data.length * 2);
  buffer.write('RIFF', 0); buffer.writeUInt32LE(buffer.length - 8, 4); buffer.write('WAVE', 8);
  buffer.write('fmt ', 12); buffer.writeUInt32LE(16, 16); buffer.writeUInt16LE(1, 20); buffer.writeUInt16LE(1, 22);
  buffer.writeUInt32LE(RATE, 24); buffer.writeUInt32LE(RATE * 2, 28); buffer.writeUInt16LE(2, 32); buffer.writeUInt16LE(16, 34);
  buffer.write('data', 36); buffer.writeUInt32LE(data.length * 2, 40);
  let peak = 0, energy = 0, clipped = 0;
  for (let i = 0; i < data.length; i++) {
    // One fixed soft limiter preserves musical layer balance and leaves headroom.
    const value = Math.tanh(data[i] * gain) * 0.88;
    const pcm = Math.round(value * 32767);
    buffer.writeInt16LE(pcm, 44 + i * 2);
    peak = Math.max(peak, Math.abs(pcm / 32768));
    energy += (pcm / 32768) ** 2;
    if (Math.abs(pcm) >= 32767) clipped++;
  }
  return { buffer, stats: { frames: data.length, duration: data.length / RATE, bytes: buffer.length, peak: +peak.toFixed(6), rms: +Math.sqrt(energy / data.length).toFixed(6), clipped_samples: clipped } };
}

fs.mkdirSync(OUT, { recursive: true });
const manifest = {
  bpm: 120, sample_rate: RATE, bit_depth: 16, channels: 1,
  combat_start: 2, combat_end: 32, combat_beats: 60, beat_duration: 0.5,
  timing: 'Zero-based combat beat b starts at 2 + 0.5 * b seconds. Fight beats are 0..59. Full file 34 seconds; no looping.',
  sections: [
    { id: 'count_in', from: 0, to: 2, description: 'Four clear preparation taps at 0, 0.5, 1, 1.5 seconds' },
    { id: 'combat_opening', from: 2, to: 6, beat_from: 0, beat_to_exclusive: 8, description: 'Kick, bass and lead arrive together; two-bar introduction' },
    { id: 'combat_groove', from: 6, to: 14, beat_from: 8, beat_to_exclusive: 24, description: 'Full groove and offbeat chord taps' },
    { id: 'break', from: 14, to: 18, beat_from: 24, beat_to_exclusive: 32, description: 'Quarter-note kick stays loud and clear; harmony and melody recede' },
    { id: 'rebuild', from: 18, to: 22, beat_from: 32, beat_to_exclusive: 40, description: 'Melody returns and leads into final burst' },
    { id: 'climax', from: 22, to: 32, beat_from: 40, beat_to_exclusive: 60, description: 'Brighter lead octave, fuller bass and restrained fills; kick remains on every beat' },
    { id: 'victory', from: 32, to: 34, description: 'Resolving chord and short upward chime, then silence' }
  ],
  mixing: 'combat.wav at -3 dB recommended. SFX default 0 dB (shot already quiet); perfect at most -3 dB if repeated frequently. No peak normalization.',
  files: {}
};
function save(name, sound, gain = 1) {
  const result = encode(sound.data, gain);
  fs.writeFileSync(path.join(OUT, name + '.wav'), result.buffer);
  manifest.files[name] = result.stats;
}

const music = renderer(34);
const roots = [45, 53, 48, 55];
const chords = [[0, 3, 7, 10], [0, 4, 7, 11], [0, 4, 7, 11], [0, 4, 7, 10]];
const motif = [[0, 2, -1, 3, 2, -1, 1, 2], [3, -1, 2, 1, 0, 1, 2, -1], [0, 1, 2, -1, 3, 2, -1, 1], [2, -1, 1, 0, 1, 2, 3, -1]];
for (let beat = 0; beat < 4; beat++) {
  music.note(beat === 3 ? 81 : 76, beat * 0.5, 0.105, 0.17, 'bell');
  music.kick(beat * 0.5, 0.19);
}
for (let beat = 0; beat < 60; beat++) {
  const at = 2 + beat * 0.5, bar = Math.floor(beat / 4), step = beat % 4;
  const chordIndex = bar % 4, root = roots[chordIndex], chord = chords[chordIndex];
  const breakdown = beat >= 24 && beat < 32, climax = beat >= 40;
  music.kick(at, step === 0 ? 0.47 : 0.43);
  music.hat(at, 0.42);
  music.hat(at + 0.25, breakdown ? 0.35 : 0.95, step === 3 && bar % 2 === 1);
  if (step % 2 === 1) music.snare(at, breakdown ? 0.38 : 1);
  music.note(root - 12 + (step === 3 ? 7 : 0), at + 0.008, 0.42, breakdown ? 0.10 : climax ? 0.23 : 0.20, 'bass');
  if (step === 0) for (let n = 0; n < 4; n++) music.note(root + 12 + chord[n], at + n * 0.008, 2.35, breakdown ? 0.014 : 0.026, 'pad');
  if (!breakdown) {
    for (let half = 0; half < 2; half++) {
      const degree = motif[bar % 4][step * 2 + half];
      if (degree >= 0) {
        const midi = root + 24 + chord[degree];
        music.note(midi, at + half * 0.25, 0.31, climax ? 0.14 : 0.12, 'lead', true);
        if (climax && half === 0) music.note(midi + 12, at, 0.23, 0.033, 'bell');
      }
    }
    if (beat >= 8) for (let n = 0; n < 3; n++) music.note(root + 12 + chord[n], at + 0.25, 0.17, 0.019, 'lead');
  } else if (step === 0) music.note(root + 24 + chord[0], at, 0.65, 0.07, 'bell', true);
  if ((beat === 39 || (climax && beat % 8 === 7)) && beat < 59) {
    music.snare(at + 0.25, 0.32);
    music.snare(at + 0.375, 0.42);
  }
}
// Deliberate cadence after the sixty playable beats; no further combat pulse.
for (const interval of [0, 3, 7, 12]) music.note(57 + interval, 32, 1.85, 0.065, 'pad');
for (let i = 0; i < 4; i++) music.note([76, 79, 81, 88][i], 32 + i * 0.14, 0.65, 0.10, 'bell', false);
for (let i = Math.round(33.4 * RATE); i < music.data.length; i++) music.data[i] *= Math.max(0, (34 - i / RATE) / 0.6);
save('combat', music, 1.24);

const shot = renderer(0.10);
shot.event(0, 0.085, t => Math.sin(TAU * (510 * t - 1250 * t * t)) * Math.exp(-t * 53) * 0.14);
save('shot', shot);
const perfect = renderer(0.28);
perfect.note(79, 0, 0.26, 0.23, 'bell');
perfect.note(84, 0.018, 0.21, 0.11, 'bell');
perfect.event(0, 0.12, t => Math.sin(TAU * 220 * t) * Math.exp(-t * 34) * 0.13);
save('perfect', perfect);
const dash = renderer(0.22);
let smoothNoise = 0;
dash.event(0, 0.20, t => {
  smoothNoise = smoothNoise * 0.72 + noise() * 0.28;
  return (smoothNoise * 0.18 + Math.sin(TAU * (170 * t + 1600 * t * t)) * 0.055) * Math.sin(Math.PI * t / 0.20) * Math.exp(-t * 3);
});
save('dash', dash);
const hurt = renderer(0.27);
hurt.event(0, 0.24, t => (Math.sin(TAU * (185 * t - 180 * t * t)) * 0.20 + Math.sin(TAU * 92 * t) * 0.10) * Math.exp(-t * 13));
save('hurt', hurt);
const kill = renderer(0.30);
for (let i = 0; i < 3; i++) kill.note([76, 79, 84][i], i * 0.045, 0.20, 0.13, 'bell');
save('kill', kill);

manifest.total_wav_bytes = Object.values(manifest.files).reduce((sum, file) => sum + file.bytes, 0);
if (manifest.total_wav_bytes >= 4000000) throw Error('Audio exceeds 4 MB budget');
if (Object.values(manifest.files).some(file => file.clipped_samples !== 0)) throw Error('Clipped output');
fs.writeFileSync(path.join(OUT, 'timeline.json'), JSON.stringify(manifest, null, 2) + '\n');
console.log(JSON.stringify(manifest, null, 2));
