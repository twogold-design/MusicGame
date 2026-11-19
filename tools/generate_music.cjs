'use strict';
const fs = require('node:fs');
const path = require('node:path');
  const INTRO = 3;
  const tracks = [
    { id: 'sunset', title: '落日汽水', subtitle: 'SUNSET SODA', bpm: 100, bars: 24, color: '#ffbc68', difficulty: '轻松律动', stars: 1, description: '把橘子汽水的气泡，敲成夏日的节拍。' },
    { id: 'neon', title: '霓虹夜行', subtitle: 'NEON CRUISE', bpm: 120, bars: 28, color: '#bba0ff', difficulty: '心跳加速', stars: 2, description: '穿过霓虹街角，接住每一个闪亮的音符。' },
    { id: 'cosmic', title: '星际派对', subtitle: 'COSMIC PARTY', bpm: 140, bars: 36, color: '#79eadf', difficulty: '派对高手', stars: 3, description: '登上猫咪的宇宙飞船，把整个银河变成舞池。' }
  ].map(t => Object.freeze({ ...t, duration: INTRO + t.bars * 240 / t.bpm + 2.5 }));

  const compositions = {
    sunset: { roots: [48, 53, 57, 55], chords: [[0, 4, 7, 11], [0, 4, 7, 11], [0, 3, 7, 10], [0, 4, 7, 10]], motifs: [[0, -1, 2, 1, 3, -1, 2, 1], [1, 2, 3, -1, 2, 1, 0, -1], [2, -1, 3, 2, 1, -1, 0, 1], [3, 2, 1, -1, 2, -1, 0, -1]], wave: 'triangle' },
    neon: { roots: [45, 53, 48, 55], chords: [[0, 3, 7, 10], [0, 4, 7, 11], [0, 4, 7, 11], [0, 4, 7, 10]], motifs: [[0, 2, -1, 3, 2, -1, 1, 2], [3, -1, 2, 1, 0, 1, 2, -1], [0, 1, 2, -1, 3, 2, -1, 1], [2, -1, 1, 0, 1, 2, 3, -1]], wave: 'square' },
    cosmic: { roots: [50, 58, 53, 60], chords: [[0, 3, 7, 10], [0, 4, 7, 11], [0, 4, 7, 11], [0, 4, 7, 10]], motifs: [[0, 2, 1, 3, -1, 2, 3, 1], [2, 1, 0, -1, 3, 2, 1, 2], [0, 1, 3, 2, 1, 2, 0, -1], [3, 2, 1, 2, 0, 1, 2, -1]], wave: 'sawtooth' }
  };

  function getTrack(id) { return tracks.find(t => t.id === id) || tracks[0]; }
  function melodicDegree(track, bar, step) {
    const motifs = compositions[track.id].motifs;
    return motifs[(bar + Math.floor(bar / 8)) % motifs.length][step];
  }

  function createChart(trackId, mode = 'normal') {
    const track = getTrack(trackId), beat = 60 / track.bpm;
    const notes = [], occupied = [-1, -1, -1, -1];
    const easy = mode === 'easy';
    for (let bar = 0; bar < track.bars; bar++) {
      const phrase = Math.floor(bar / 8);
      for (let step = 0; step < 8; step++) {
        const degree = melodicDegree(track, bar, step);
        if (degree < 0) continue;
        if (easy && step % 2) continue;
        if (!easy && bar < 4 && step % 2) continue;
        if (!easy && track.id === 'sunset' && step % 2 && bar % 2 === 0) continue;
        const time = INTRO + (bar * 4 + step / 2) * beat;
        const lane = (degree + Math.floor(bar / 2) + phrase) % 4;
        if (occupied[lane] > time - 0.12) continue;
        let duration = 0;
        if (bar >= 4 && bar % 4 === 3 && step === (easy ? 0 : 4)) duration = beat * (easy ? 1 : 1.5);
        if (time + duration > track.duration - 2) continue;
        notes.push({ time, lane, duration });
        occupied[lane] = time + Math.max(duration, beat / 4);
        // A few musical two-hand accents are introduced only in the final third.
        if (!easy && track.stars >= 2 && bar > track.bars * 0.65 && bar % 4 === 0 && step === 0) {
          const secondLane = (lane + 2) % 4;
          if (occupied[secondLane] < time - 0.12) {
            notes.push({ time, lane: secondLane, duration: 0 });
            occupied[secondLane] = time + beat / 4;
          }
        }
      }
    }
    return notes.sort((a, b) => a.time - b.time || a.lane - b.lane);
  }

const ROOT = path.resolve(__dirname, '..');
const RATE = 22050;
const hz = midi => 440 * 2 ** ((midi - 69) / 12);
const TAU = Math.PI * 2;
let randomState = 19473;
function noise() {
  randomState ^= randomState << 13; randomState ^= randomState >>> 17; randomState ^= randomState << 5;
  return (randomState >>> 0) / 2147483648 - 1;
}

function renderTrack(track) {
  const data = new Float32Array(Math.ceil(track.duration * RATE));
  const beat = 60 / track.bpm, comp = compositions[track.id];
  function tone(midi, at, duration, kind, amp, echo = false) {
    const frequency = hz(midi), start = Math.round(at * RATE), count = Math.ceil((duration + 0.1) * RATE);
    for (let i = 0; i < count && start + i < data.length; i++) {
      const seconds = i / RATE, phase = TAU * frequency * seconds;
      const envelope = Math.min(1, seconds / (kind === 'pad' ? 0.12 : 0.008)) * Math.exp(-seconds / (duration * (kind === 'pad' ? 1.15 : 0.55))) * Math.min(1, (duration + 0.1 - seconds) / 0.1);
      let value;
      if (kind === 'pad') value = Math.sin(phase) * 0.8 + Math.sin(phase * 2.002) * 0.14 + Math.sin(phase * 0.998) * 0.1;
      else if (kind === 'bass') value = Math.sin(phase) * 0.8 + Math.sin(phase * 2) * 0.18 + Math.sin(phase * 3) * 0.08;
      else if (kind === 'bell') value = Math.sin(phase + Math.sin(phase * 2) * 0.7 * Math.exp(-seconds * 12)) * 0.85 + Math.sin(phase * 3) * 0.08;
      else value = Math.sin(phase) * 0.75 + Math.sin(phase * 2) * 0.16 + Math.sin(phase * 3) * 0.09 * Math.exp(-seconds * 7);
      const sample = value * envelope * amp;
      data[start + i] += sample;
      if (echo) {
        const delayed = start + i + Math.round(beat * 0.75 * RATE);
        if (delayed < data.length) data[delayed] += sample * 0.16;
        const delayed2 = delayed + Math.round(beat * 0.75 * RATE);
        if (delayed2 < data.length) data[delayed2] += sample * 0.055;
      }
    }
  }
  function kick(at, strength = 1) {
    const start = Math.round(at * RATE), count = Math.ceil(RATE * 0.3);
    let phase = 0;
    for (let i = 0; i < count && start + i < data.length; i++) {
      const t = i / RATE;
      phase += TAU * (43 + 110 * Math.exp(-t * 35)) / RATE;
      data[start + i] += Math.sin(phase) * Math.exp(-t * 19) * Math.min(1, t * 800) * 0.46 * strength;
    }
  }
  function percussion(at, snare, open = false, strength = 1) {
    const start = Math.round(at * RATE), duration = snare ? 0.18 : open ? 0.17 : 0.055;
    const count = Math.ceil(RATE * duration);
    let previous = 0;
    for (let i = 0; i < count && start + i < data.length; i++) {
      const t = i / RATE, next = noise(), high = next - previous * (snare ? 0.48 : 0.92);
      previous = next;
      const body = snare ? Math.sin(t * TAU * 185) * Math.exp(-t * 45) * 0.07 : 0;
      data[start + i] += (high * (snare ? 0.11 : 0.033) * Math.exp(-t / (duration * 0.2)) + body) * strength;
    }
  }
  for (let i = 0; i < 3; i++) tone(76, i, 0.06, 'bell', 0.08);
  for (let bar = 0; bar < track.bars; bar++) {
    const chordIndex = Math.floor(bar / 2) % 4, root = comp.roots[chordIndex], chord = comp.chords[chordIndex];
    const breakdown = bar >= Math.floor(track.bars / 2) && bar < Math.floor(track.bars / 2) + 4;
    const outro = bar >= track.bars - 2;
    for (let step = 0; step < 8; step++) {
      const at = INTRO + (bar * 4 + step / 2) * beat;
      if (step === 0) for (let n = 0; n < 4; n++) tone(root + 12 + chord[n], at + n * 0.014, beat * 3.6, 'pad', breakdown ? 0.045 : 0.033);
      if (step % 2 === 0) {
        if (!breakdown || step === 0) kick(at, outro ? 0.75 : 1);
        tone(root - 12 + (step === 6 ? 7 : 0), at + 0.01, beat * 0.65, 'bass', 0.24);
      }
      if ((step === 2 || step === 6) && !breakdown) percussion(at, true, false, outro ? 0.75 : 1);
      if (!breakdown || step % 2) percussion(at, false, step === 7 && bar % 2 === 1, step % 2 ? 0.9 : 0.5);
      const degree = melodicDegree(track, bar, step);
      if (degree >= 0) {
        const octave = bar % 8 >= 6 ? 36 : 24;
        tone(root + octave + chord[degree], at, beat * (step === 6 ? 0.68 : 0.42), track.id === 'sunset' ? 'bell' : 'lead', 0.14, true);
      }
      if (!breakdown && bar >= 8 && step % 2 === 1) tone(root + 12 + chord[(step + bar) % 4], at, beat * 0.16, 'bell', 0.035, true);
      if (bar % 8 === 7 && step >= 6 && !breakdown) percussion(at + beat / 4, true, false, 0.5);
    }
  }
  const end = INTRO + track.bars * 4 * beat;
  for (const interval of comp.chords[0]) tone(comp.roots[0] + 12 + interval, end, 1.6, 'pad', 0.05, true);
  let peak = 0, squares = 0;
  for (let i = 0; i < data.length; i++) {
    const fade = Math.min(1, (track.duration - i / RATE) / 0.8);
    data[i] = Math.tanh(data[i] * 1.4) * 0.88 * fade;
    peak = Math.max(peak, Math.abs(data[i])); squares += data[i] ** 2;
  }
  const buffer = Buffer.alloc(44 + data.length * 2);
  buffer.write('RIFF', 0); buffer.writeUInt32LE(buffer.length - 8, 4); buffer.write('WAVE', 8);
  buffer.write('fmt ', 12); buffer.writeUInt32LE(16, 16); buffer.writeUInt16LE(1, 20); buffer.writeUInt16LE(1, 22);
  buffer.writeUInt32LE(RATE, 24); buffer.writeUInt32LE(RATE * 2, 28); buffer.writeUInt16LE(2, 32); buffer.writeUInt16LE(16, 34);
  buffer.write('data', 36); buffer.writeUInt32LE(data.length * 2, 40);
  for (let i = 0; i < data.length; i++) buffer.writeInt16LE(Math.round(data[i] * 32767), 44 + i * 2);
  fs.writeFileSync(path.join(ROOT, 'assets', 'audio', track.id + '.wav'), buffer);
  return { bytes: buffer.length, peak: +peak.toFixed(3), rms: +Math.sqrt(squares / data.length).toFixed(3) };
}

function verifyChart(track, notes) {
  const occupied = [-1, -1, -1, -1];
  for (let i = 0; i < notes.length; i++) {
    const note = notes[i];
    if (i && notes[i - 1].time > note.time) throw Error('Unsorted chart');
    if (note.time < 3 || note.time + note.duration > track.duration - 2) throw Error('Out of range note');
    if (occupied[note.lane] > note.time - 0.1) throw Error('Overlapping hold');
    occupied[note.lane] = note.time + note.duration;
  }
}

fs.mkdirSync(path.join(ROOT, 'assets', 'audio'), { recursive: true });
fs.mkdirSync(path.join(ROOT, 'assets', 'charts'), { recursive: true });
for (const track of tracks) {
  const counts = {};
  for (const mode of ['easy', 'normal']) {
    const notes = createChart(track.id, mode);
    verifyChart(track, notes);
    const chart = { ...track, mode, notes };
    fs.writeFileSync(path.join(ROOT, 'assets', 'charts', track.id + '_' + mode + '.json'), JSON.stringify(chart));
    counts[mode] = { notes: notes.length, holds: notes.filter(n => n.duration > 0).length };
  }
  console.log(JSON.stringify({ id: track.id, duration: track.duration, ...renderTrack(track), charts: counts }));
}


