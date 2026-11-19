'use strict';
// The backing track intentionally has NO lead: the player's actions play it.
// Original synthesis, deterministic, standard library only; all writes on M:.
const fs = require('node:fs');
const path = require('node:path');
const ROOT = path.resolve(__dirname, '..');
const OUT = path.join(ROOT, 'assets', 'audio', 'groove');
const RATE = 22050, TAU = Math.PI * 2, BEAT = 0.5;
const hz = midi => 440 * 2 ** ((midi - 69) / 12);
let seed = 284957;
const noise = () => {
  seed ^= seed << 13; seed ^= seed >>> 17; seed ^= seed << 5;
  return (seed >>> 0) / 2147483648 - 1;
};
function renderer(seconds) {
  const data = new Float64Array(Math.round(seconds * RATE));
  function event(at, length, sample, attack = 0.0015) {
    const start = Math.round(at * RATE), count = Math.ceil(length * RATE);
    for (let i = 0; i < count && start + i < data.length; i++) {
      const t = i / RATE;
      const edge = Math.max(0, Math.min(1, attack > 0 ? t / attack : 1, (length - t) / 0.014));
      data[start + i] += sample(t) * edge;
    }
  }
  function note(midi, at, length, amp, kind = 'chord') {
    const frequency = hz(midi);
    event(at, length, t => {
      const phase = TAU * frequency * t;
      const wave = kind === 'bass' ? Math.sin(phase) * 0.8 + Math.sin(phase * 2) * 0.25 + Math.sin(phase * 3) * 0.08 : Math.sin(phase) * 0.84 + Math.sin(phase * 2) * 0.12;
      return wave * Math.exp(-t / (length * 0.43)) * amp;
    }, kind === 'bass' ? 0.004 : 0.011);
  }
  function kick(at, amp = 0.54) {
    event(at, 0.245, t => {
      const phase = TAU * (57 * t + 96 / 43 * (1 - Math.exp(-43 * t)));
      return (Math.sin(phase) * 0.88 + Math.sin(phase * 2) * 0.25 + Math.sin(phase * 3) * 0.1) * Math.exp(-t * 20) * amp;
    }, 0.0008);
    event(at, 0.025, t => Math.sin(TAU * 1280 * t) * Math.exp(-t * 150) * 0.068, 0.0003);
  }
  function hat(at, amp = 0.045, open = false) {
    let previous = 0;
    const length = open ? 0.13 : 0.043;
    event(at, length, t => {
      const value = noise(), high = (value - previous * 0.78) * 0.55;
      previous = value;
      return high * Math.exp(-t / (length * 0.21)) * amp;
    });
  }
  function clap(at, amp = 0.13, low = false) {
    let smoothed = 0;
    event(at, low ? 0.19 : 0.12, t => {
      smoothed = smoothed * 0.58 + noise() * 0.42;
      const noiseEnvelope = Math.exp(-t * 31) * (0.65 + Math.cos(TAU * 90 * t) * 0.35);
      const body = Math.sin(TAU * (low ? 176 : 265) * t) * Math.exp(-t * 35);
      return (smoothed * noiseEnvelope * 0.7 + body * 0.55) * amp;
    }, 0.0008);
  }
  return { data, event, note, kick, hat, clap };
}

function encode(data) {
  const b = Buffer.alloc(44 + data.length * 2);
  b.write('RIFF', 0); b.writeUInt32LE(b.length - 8, 4); b.write('WAVE', 8);
  b.write('fmt ', 12); b.writeUInt32LE(16, 16); b.writeUInt16LE(1, 20); b.writeUInt16LE(1, 22);
  b.writeUInt32LE(RATE, 24); b.writeUInt32LE(RATE * 2, 28); b.writeUInt16LE(2, 32); b.writeUInt16LE(16, 34);
  b.write('data', 36); b.writeUInt32LE(data.length * 2, 40);
  // 20Hz high-pass removes DC/inaudible rumble before a common soft limiter.
  const coefficient = Math.exp(-TAU * 20 / RATE);
  let previousIn = 0, previousOut = 0, peak = 0, energy = 0, mean = 0, clipped = 0, firstAudible = -1;
  for (let i = 0; i < data.length; i++) {
    const filtered = coefficient * (previousOut + data[i] - previousIn);
    previousIn = data[i]; previousOut = filtered;
    const value = Math.tanh(filtered * 1.18) * 0.88;
    const pcm = Math.round(value * 32767);
    b.writeInt16LE(pcm, 44 + i * 2);
    const normalized = pcm / 32768;
    peak = Math.max(peak, Math.abs(normalized)); energy += normalized ** 2; mean += normalized;
    if (Math.abs(pcm) >= 32767) clipped++;
    if (firstAudible < 0 && Math.abs(normalized) >= 0.001) firstAudible = i;
  }
  return { buffer: b, stats: { frames: data.length, duration: data.length / RATE, bytes: b.length, peak: +peak.toFixed(6), rms: +Math.sqrt(energy / data.length).toFixed(6), dc_mean: +(mean / data.length).toFixed(8), first_audible_frame: firstAudible, onset_ms: +(firstAudible / RATE * 1000).toFixed(4), clipped_samples: clipped } };
}

fs.mkdirSync(OUT, { recursive: true });
const roots = [45, 53, 48, 55];
const chords = [[0, 3, 7, 10], [0, 4, 7, 11], [0, 4, 7, 11], [0, 4, 7, 10]];
// Fifth -> root for each bar, an intentionally simple repeatable action motif.
const melodyMidi = [76, 81, 72, 77, 79, 84, 74, 79];
const metadata = {
  bpm: 120, beat_duration: BEAT, sample_rate: RATE, bit_depth: 16, channels: 1,
  count_in_seconds: 2, combat_start: 2, combat_end: 32, duration: 34,
  source_beats: 'Combat beat 0 begins at WAV second 2.0; beat 59 at 31.5. Prepare taps are 0,0.5,1,1.5. First preparation tap is beat -4.',
  bars: '15 combat bars plus the preparation bar; no full lead exists in bed.wav.',
  mapping: { formula: 'floor(beat / 4) % 4 * 2 + round(beat) % 2', rounding: 'nearest integer, ties towards positive infinity, e.g. round(43.5)=44', note: 'Use cue.sample directly to avoid cross-language rounding differences.' },
  latency_guidance: 'For Godot WAV stream use sample playback in web when available. Drive judgement from bed playback position + AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency(). Trigger player sample immediately on accepted action; do not add output_latency again or wait for the next beat. Hardware response latency remains; use local input offset calibration. No silent padding in action samples.',
  mixing: 'Fixed balance, no sample normalization. Start bed at -3 dB, shot at 0 dB, dash at 0 dB, miss at 0 dB. Reserve master headroom when voices overlap; limit simultaneous shot voices to 2. Bed plus one action remains below 0.9 even by sum-of-peaks bound.',
  sections: [
    { from: 0, to: 2, name: 'count_in' },
    { from: 2, to: 6, name: 'opening' },
    { from: 6, to: 22, name: 'four_beat_shot_shot_dash_shot' },
    { from: 22, to: 32, name: 'climax_with_four_extra_halfbeat_shots' },
    { from: 32, to: 34, name: 'victory_cadence' }
  ],
  sample_notes: melodyMidi.map((midi, index) => ({ index, sample: 'shot_' + index + '.wav', midi, frequency_hz: +hz(midi).toFixed(4), chord_index: Math.floor(index / 2), chord: ['Am7', 'Fmaj7', 'Cmaj7', 'G7'][Math.floor(index / 2)] })),
  cues: [], files: {}, validation: {}
};
function save(name, sound) {
  const result = encode(sound.data);
  fs.writeFileSync(path.join(OUT, name + '.wav'), result.buffer);
  metadata.files[name] = result.stats;
}

const bed = renderer(34);
for (let i = 0; i < 4; i++) {
  bed.kick(i * BEAT, i === 3 ? 0.39 : 0.29);
  bed.note(i === 3 ? 79 : 74, i * BEAT, 0.075, 0.08, 'chord');
}
for (let beat = 0; beat < 60; beat++) {
  const time = 2 + beat * BEAT, step = beat % 4, bar = Math.floor(beat / 4), ci = bar % 4;
  const root = roots[ci], chord = chords[ci], climax = beat >= 40;
  bed.kick(time, step === 0 ? 0.56 : 0.52);
  bed.hat(time, 0.022);
  bed.hat(time + 0.25, climax ? 0.058 : 0.039, step === 3 && bar % 2 === 1);
  // Beat position 2 carries an unmistakable low clap, matching the dash cue.
  if (step === 2 && beat >= 8) bed.clap(time, 0.23, true);
  else if (step === 1 || step === 3) bed.clap(time, 0.12, false);
  bed.note(root - 12 + (step === 3 ? 7 : 0), time + 0.008, 0.36, climax ? 0.18 : 0.16, 'bass');
  if (step === 0) for (const interval of chord) bed.note(root + 12 + interval, time + 0.04, 1.75, 0.021);
  // Chord stabs and syncopated bass, leaving the whole lead register to shots.
  if (step === 1 || step === 3) for (const interval of chord.slice(0, 3)) bed.note(root + 12 + interval, time + 0.25, 0.14, climax ? 0.022 : 0.014);
  if (climax && step === 3) bed.note(root - 12 + 7, time + 0.25, 0.15, 0.09, 'bass');
  if ([43, 47, 51, 55].includes(beat)) {
    // An audible offbeat hi-hat answers the additional player melody cue.
    bed.hat(time + 0.25, 0.084);
  }
}
for (const interval of [0, 3, 7, 12]) bed.note(57 + interval, 32, 1.8, 0.05);
for (let i = Math.round(33.3 * RATE); i < bed.data.length; i++) bed.data[i] *= Math.max(0, (34 - i / RATE) / 0.7);
save('bed', bed);

for (let index = 0; index < 8; index++) {
  const sound = renderer(0.23), frequency = hz(melodyMidi[index]);
  // No pre-roll and no slow attack: the very first sample interval is audible.
  sound.event(0, 0.23, t => {
    const phase = TAU * frequency * t;
    const body = Math.sin(phase + Math.sin(phase * 2) * 0.22 * Math.exp(-t * 35));
    return (body * 0.25 + Math.sin(phase * 2) * 0.035 * Math.exp(-t * 40)) * Math.exp(-t * 15);
  }, 0);
  save('shot_' + index, sound);
}
const dash = renderer(0.23);
let smooth = 0;
dash.event(0, 0.23, t => {
  smooth = smooth * 0.74 + noise() * 0.26;
  const phase = TAU * (205 * t - 160 * t * t);
  const body = Math.sin(phase) * 0.23 + Math.sin(phase * 2) * 0.055;
  const clap = smooth * 0.15 * (0.65 + Math.cos(TAU * 80 * t) * 0.35);
  return (body + clap) * Math.exp(-t * 21);
}, 0.0001);
save('dash', dash);
const miss = renderer(0.09);
miss.event(0, 0.09, t => Math.sin(TAU * 145 * t) * Math.exp(-t * 52) * 0.052, 0);
save('miss', miss);

for (const beat of [...Array.from({ length: 60 }, (_, i) => i), 43.5, 47.5, 51.5, 55.5].sort((a,b) => a-b)) {
  const action = beat >= 8 && Number.isInteger(beat) && beat % 4 === 2 ? 'dash' : 'shot';
  const sampleIndex = Math.floor(beat / 4) % 4 * 2 + Math.round(beat) % 2;
  metadata.cues.push({ index: metadata.cues.length, beat, time: 2 + beat * BEAT, action, sample_index: action === 'shot' ? sampleIndex : -1, sample: action === 'shot' ? 'shot_' + sampleIndex + '.wav' : 'dash.wav' });
}

// Pre-render the accepted-action response into two sparse, phase-locked tracks.
// Copy the already quantized PCM directly: no second filter, limiter or gain.
// Alternating global cue indices guarantee each track has a silent gate gap.
const responseNames = ['response_even', 'response_odd'];
metadata.response_stems = {
  paths: responseNames.map(name => name + '.wav'),
  assignment: 'Global cue index modulo 2; use cue.stem_channel.',
  playback: 'Start both 34s response tracks at 0 in the same frame as bed.wav. Keep tracks continuously playing at -80dB when not armed. For an accepted early cue open its channel immediately, then close after cue.time+cue.note_duration, during the silent gap. Do not reopen a track for late input; play the independent sample immediately instead.',
  gain: '0 dB response track reproduces the original action sample bit-for-bit; bed -3dB. Do not normalize these tracks.',
  late_policy: 'For input received after cue.time, leave response track gated and use the independent action sample.',
};
for (const cue of metadata.cues) {
  cue.stem_channel = cue.index % 2;
  cue.stem_path = responseNames[cue.stem_channel] + '.wav';
  cue.note_duration = metadata.files[cue.sample.replace('.wav', '')].duration;
}
for (let channel = 0; channel < 2; channel++) {
  const pcm = new Int32Array(metadata.files.bed.frames);
  for (const cue of metadata.cues.filter(cue => cue.stem_channel === channel)) {
    const sample = fs.readFileSync(path.join(OUT, cue.sample));
    const start = Math.round(cue.time * RATE), count = (sample.length - 44) / 2;
    for (let i = 0; i < count; i++) pcm[start + i] += sample.readInt16LE(44 + i * 2);
  }
  const b = Buffer.alloc(44 + pcm.length * 2);
  fs.readFileSync(path.join(OUT, 'bed.wav')).copy(b, 0, 0, 44);
  b.writeUInt32LE(b.length - 8, 4); b.writeUInt32LE(pcm.length * 2, 40);
  let peak = 0, energy = 0, mean = 0, firstAudible = -1;
  for (let i = 0; i < pcm.length; i++) {
    if (Math.abs(pcm[i]) >= 32767) throw Error('Response track clipping');
    b.writeInt16LE(pcm[i],44+i*2);
    const sample = pcm[i] / 32768;
    peak = Math.max(peak,Math.abs(sample)); energy += sample ** 2; mean += sample;
    if (firstAudible < 0 && Math.abs(sample)>=0.001) firstAudible=i;
  }
  const name = responseNames[channel];
  fs.writeFileSync(path.join(OUT,name+'.wav'),b);
  metadata.files[name] = { frames: pcm.length, duration: pcm.length/RATE, bytes: b.length, peak: +peak.toFixed(6), rms: +Math.sqrt(energy/pcm.length).toFixed(6), dc_mean: +(mean/pcm.length).toFixed(8), first_audible_frame: firstAudible, onset_ms: +(firstAudible/RATE*1000).toFixed(4), clipped_samples: 0, bit_exact_copy: true };
}

// Re-open the actual PCM outputs, rather than testing only float synthesis.
let checks = 0, bytes = 0;
for (const [name, info] of Object.entries(metadata.files)) {
  const b = fs.readFileSync(path.join(OUT, name + '.wav'));
  if (b.toString('ascii', 0, 4) !== 'RIFF' || b.toString('ascii', 8, 12) !== 'WAVE' || b.readUInt16LE(20) !== 1 || b.readUInt16LE(22) !== 1 || b.readUInt32LE(24) !== RATE || b.readUInt16LE(34) !== 16) throw Error('WAV format: ' + name);
  if ((b.length - 44) / 2 !== info.frames || b.readUInt32LE(40) !== info.frames * 2) throw Error('Frame count: ' + name);
  let clipped = 0;
  for (let i = 44; i < b.length; i += 2) if (Math.abs(b.readInt16LE(i)) >= 32767) clipped++;
  if (clipped || info.peak >= 0.9 || Math.abs(info.dc_mean) > 0.001) throw Error('PCM integrity: ' + name);
  if (name !== 'bed' && !name.startsWith('response_') && info.onset_ms > 1) throw Error('Slow action onset: ' + name);
  checks += 3; bytes += b.length;
}
if (bytes >= 6000000 || metadata.cues.length !== 64 || metadata.cues.filter(c => c.action === 'dash').length !== 13) throw Error('Budget or chart consistency');
checks += 3;
const b = fs.readFileSync(path.join(OUT, 'bed.wav'));
const lowBand = new Float64Array(metadata.files.bed.frames);
let filtered = 0;
const coefficient = 1 - Math.exp(-TAU * 250 / RATE);
for (let i = 0; i < lowBand.length; i++) {
  filtered += coefficient * (b.readInt16LE(44 + 2 * i) / 32768 - filtered);
  lowBand[i] = filtered;
}
function rmsAt(time, length) {
  let sum = 0; const start = Math.round(time * RATE), n = Math.round(length * RATE);
  for (let i = start; i < start + n; i++) sum += lowBand[i] ** 2;
  return Math.sqrt(sum / n);
}
const pulseRatios = Array.from({ length: 60 }, (_, beat) => rmsAt(2 + beat * BEAT + 0.007, 0.07) / Math.max(0.00001, rmsAt(2 + beat * BEAT + 0.18, 0.07)));
if (Math.min(...pulseRatios) < 2) throw Error('Quarter-note kick obscured');
checks++;
const maxShot = Math.max(...Object.entries(metadata.files).filter(([name]) => name.startsWith('shot_')).map(([, info]) => info.peak));
metadata.validation = { checks, passed: true, total_wav_bytes: bytes, highpass_hz: 20, clipped_samples: 0, quarter_note_lowband_pulse_ratio_min: +Math.min(...pulseRatios).toFixed(3), quarter_note_lowband_pulse_ratio_average: +(pulseRatios.reduce((a,b) => a+b) / 60).toFixed(3), peak_bound_bed_minus3db_plus_one_shot: +(metadata.files.bed.peak * 10 ** (-3 / 20) + maxShot).toFixed(6), shot_cues: 51, dash_cues: 13 };
if (metadata.validation.peak_bound_bed_minus3db_plus_one_shot >= 0.9) throw Error('Mix lacks headroom');
fs.writeFileSync(path.join(OUT, 'metadata.json'), JSON.stringify(metadata, null, 2) + '\n');
console.log(JSON.stringify({ files: metadata.files, validation: metadata.validation }, null, 2));
