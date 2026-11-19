'use strict';
// A 24-bar original arrangement for the continuous 3D wrecking stage.
// Standard-library-only, deterministic, with bit-exact sparse response stems.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const ROOT = path.resolve(__dirname, '..');
const OUT = path.join(ROOT, 'assets', 'audio', 'wreck3d');
const RATE = 22050, TAU = Math.PI * 2, BEAT = 0.5, LENGTH = 52;
const hz = midi => 440 * 2 ** ((midi - 69) / 12);
let seed = 918275;
function noise() {
  seed ^= seed << 13; seed ^= seed >>> 17; seed ^= seed << 5;
  return (seed >>> 0) / 2147483648 - 1;
}
function renderer(seconds) {
  const data = new Float64Array(Math.round(seconds * RATE));
  function event(at, length, sample, attack = 0.001) {
    const start = Math.round(at * RATE), count = Math.ceil(length * RATE);
    for (let i = 0; i < count && start + i < data.length; i++) {
      if (start + i < 0) continue;
      const t = i / RATE;
      const envelope = Math.max(0, Math.min(1, attack ? t / attack : 1, (length - t) / 0.012));
      data[start + i] += sample(t) * envelope;
    }
  }
  function note(midi, at, length, amplitude, voice = 'keys', echo = false) {
    const frequency = hz(midi);
    const sample = t => {
      const phase = TAU * frequency * t;
      const decay = Math.exp(-t / (length * (voice === 'pad' ? 0.75 : voice === 'bass' ? 0.5 : 0.33)));
      let wave;
      if (voice === 'bass') wave = Math.sin(phase) * 0.80 + Math.sin(phase * 2) * 0.22 + Math.sin(phase * 3) * 0.1 * Math.exp(-t * 15);
      else if (voice === 'pad') wave = Math.sin(phase) * 0.83 + Math.sin(phase * 2.003) * 0.13 + Math.sin(phase * 0.997) * 0.07;
      else if (voice === 'pluck') wave = Math.sin(phase + Math.sin(phase * 2) * 0.45 * Math.exp(-t * 22)) * 0.91;
      else wave = Math.sin(phase) * 0.8 + Math.sin(phase * 2) * 0.15 + Math.sin(phase * 3) * 0.06 * Math.exp(-t * 18);
      return wave * decay * amplitude;
    };
    event(at, length, sample, voice === 'pad' ? 0.045 : voice === 'bass' ? 0.004 : 0.001);
    if (echo) {
      event(at + 0.375, length, t => sample(t) * 0.13);
      event(at + 0.75, length, t => sample(t) * 0.04);
    }
  }
  function kick(at, amplitude = 0.45) {
    event(at, 0.25, t => {
      const phase = TAU * (55 * t + 104 / 42 * (1 - Math.exp(-t * 42)));
      return (Math.sin(phase) * 0.87 + Math.sin(phase * 2) * 0.25 + Math.sin(phase * 3) * 0.08) * Math.exp(-t * 20) * amplitude;
    }, 0.0008);
    event(at, 0.026, t => Math.sin(TAU * 1220 * t) * Math.exp(-t * 145) * 0.055, 0.0003);
  }
  function hat(at, amp = 0.04, open = false) {
    let last = 0;
    const length = open ? 0.18 : 0.05;
    event(at, length, t => {
      const n = noise(), high = (n - last * 0.85) * 0.5;
      last = n;
      return high * Math.exp(-t / (length * 0.21)) * amp;
    });
  }
  function snare(at, amp = 0.15, rim = false) {
    let filtered = 0;
    event(at, rim ? 0.085 : 0.15, t => {
      filtered = filtered * 0.42 + noise() * 0.58;
      const tone = Math.sin(TAU * (rim ? 880 : 192) * t) * Math.exp(-t * (rim ? 70 : 42));
      return (filtered * Math.exp(-t * 33) * (rim ? 0.2 : 0.6) + tone * 0.55) * amp;
    }, 0.0005);
  }
  function clap(at, amp = 0.1) {
    let low = 0;
    event(at, 0.12, t => {
      low = low * 0.62 + noise() * 0.38;
      return low * Math.exp(-t * 35) * (0.6 + Math.cos(TAU * 80 * t) * 0.4) * amp;
    });
  }
  function tom(at, midi, amp = 0.12) {
    const frequency = hz(midi);
    event(at, 0.19, t => Math.sin(TAU * (frequency * t + frequency * 0.25 / 30 * (1 - Math.exp(-30 * t)))) * Math.exp(-t * 23) * amp);
  }
  function cymbal(at, amp = 0.07, length = 0.65) {
    let previous = 0;
    event(at, length, t => {
      const n = noise(), high = (n - previous * 0.65) * 0.45;
      previous = n;
      const metallic = (Math.sin(TAU * 2911 * t) + Math.sin(TAU * 4093 * t)) * 0.07;
      return (high + metallic) * Math.exp(-t / (length * 0.23)) * amp;
    });
  }
  return { data, event, note, kick, hat, snare, clap, tom, cymbal };
}

function wavHeader(frames) {
  const b = Buffer.alloc(44 + frames * 2);
  b.write('RIFF', 0); b.writeUInt32LE(b.length - 8, 4); b.write('WAVE', 8);
  b.write('fmt ', 12); b.writeUInt32LE(16, 16); b.writeUInt16LE(1, 20); b.writeUInt16LE(1, 22);
  b.writeUInt32LE(RATE, 24); b.writeUInt32LE(RATE * 2, 28); b.writeUInt16LE(2, 32); b.writeUInt16LE(16, 34);
  b.write('data', 36); b.writeUInt32LE(frames * 2, 40);
  return b;
}
function encode(data) {
  const b = wavHeader(data.length), coefficient = Math.exp(-TAU * 25 / RATE);
  let lastIn = 0, lastOut = 0;
  for (let i = 0; i < data.length; i++) {
    const filtered = coefficient * (lastOut + data[i] - lastIn);
    lastIn = data[i]; lastOut = filtered;
    const finalFade = Math.min(1, (data.length - 1 - i) / (RATE * 0.009));
    b.writeInt16LE(Math.round(Math.tanh(filtered * 1.16) * 0.86 * Math.max(0, finalFade) * 32767), 44 + i * 2);
  }
  return b;
}
function stats(b) {
  let peak = 0, sum = 0, dc = 0, clipped = 0, first = -1;
  const frames = (b.length - 44) / 2;
  for (let i = 0; i < frames; i++) {
    const pcm = b.readInt16LE(44 + i * 2), sample = pcm / 32768;
    peak = Math.max(peak, Math.abs(sample)); sum += sample * sample; dc += sample;
    if (Math.abs(pcm) >= 32767) clipped++;
    if (first < 0 && Math.abs(sample) > 0.001) first = i;
  }
  return { frames, duration: frames / RATE, bytes: b.length, peak: +peak.toFixed(6), rms: +Math.sqrt(sum / frames).toFixed(6), dc_mean: +(dc / frames).toFixed(8), onset_ms: +(first / RATE * 1000).toFixed(4), clipped_samples: clipped };
}

fs.mkdirSync(OUT, { recursive: true });
const roots = [45, 53, 48, 55];
const chordNotes = [[0, 3, 7, 10], [0, 4, 7, 11], [0, 4, 7, 11], [0, 4, 7, 10]];
const progression = [0,1,2,3, 0,1,2,3, 0,0,1,3, 0,1,2,3, 2,1,0,3, 0,1,2,3];
const sections = [
  { id: 'verse_intro', from: 2, to: 10, bar_from: 0, bar_to: 4, description: 'Four-on-floor pulse, warm keys, sparse arpeggio; individual bars build.' },
  { id: 'funk_groove', from: 10, to: 18, bar_from: 4, bar_to: 8, description: 'Syncopated octave bass, rim/clap layers and sixteenth-note shaker accents.' },
  { id: 'break', from: 18, to: 26, bar_from: 8, bar_to: 12, description: 'Kick remains on every quarter note; drums thin, sustained pad and sparse bells leave space.' },
  { id: 'drop', from: 26, to: 34, bar_from: 12, bar_to: 16, description: 'Full kick/snare/clap, crash, animated octave bass and rising arpeggio answers.' },
  { id: 'melodic_lift', from: 34, to: 42, bar_from: 16, bar_to: 20, description: 'Harmonic variation, bright plucked motif and ride cymbal; player strikes complete the high melody.' },
  { id: 'final_fill', from: 42, to: 50, bar_from: 20, bar_to: 24, description: 'Final build, varied snare/tom fills, extra halfbeat answers; no identical bar loops.' },
  { id: 'cadence', from: 50, to: 52, description: 'Resolved chord and fading cymbal; no more gameplay cues.' }
];
const metadata = {
  title: 'Wreck the Night / 拆掉这夜晚', bpm: 120, sample_rate: RATE, bit_depth: 16, channels: 1,
  beat_duration: BEAT, count_in_seconds: 2, combat_start: 2, combat_end: 50, duration: LENGTH, frames: LENGTH * RATE,
  bars: 24, battle_beats: 96, cue_count: 102, sections,
  all_cues_action: 'tap; every cue may be charged/released as a heavy hit; voice describes timbre only',
  cue_time_formula: '2 + beat * 0.5 seconds', extra_halfbeats: [15.5,31.5,47.5,63.5,79.5,95.5],
  chord_progression: progression.map(ci => ['Am7','Fmaj7','Cmaj7','G7'][ci]),
  response_stems: { paths: ['response_even.wav','response_odd.wav'], assignment: 'global cue.index % 2; never beat parity', exact_pcm_copy: true, gain: '0dB reconstructs each original sample bit-for-bit', playback: 'Preload all streams, start bed and both response tracks together from zero. Keep response tracks at -80dB until an accepted early cue; open its channel and close at cue.time+note_duration in the following silent gap. Accepted late cue uses independent sample, never a late gate.' },
  mixing: 'Bed -3dB, response -1dB, material destruction about -5dB and heavy thump -7dB recommended. No normalization. Keep material voice count bounded. Master limiter recommended if many breakables sound at once.',
  timing_guidance: 'Judgement uses heard playback time; sample-exact response is already placed in the phase-locked stem. Do not schedule dynamic play() for an early response; late inputs may use independent shot_N/dash samples immediately.',
  files: {}, cues: [], validation: {}
};
function save(name, sound) {
  const b = encode(sound.data);
  fs.writeFileSync(path.join(OUT, name + '.wav'), b);
  metadata.files[name] = stats(b);
}

const bed = renderer(LENGTH);
for (let b = 0; b < 4; b++) {
  bed.kick(b * BEAT, b === 3 ? 0.35 : 0.26);
  bed.note(b === 3 ? 81 : 76, b * BEAT, 0.07, 0.065, 'pluck');
}
const bassPatterns = [
  [[0,0,0.30],[0.75,7,0.17],[1.5,0,0.17],[2,12,0.27],[2.75,7,0.15],[3.5,0,0.20]],
  [[0,0,0.26],[0.5,12,0.16],[1.25,7,0.18],[1.75,0,0.16],[2.5,12,0.20],[3,7,0.16],[3.75,0,0.12]],
  [[0,0,0.32],[1.5,7,0.20],[2,0,0.29],[2.75,12,0.16],[3.5,7,0.18]],
  [[0,0,0.24],[0.75,7,0.16],[1.5,12,0.17],[2.25,0,0.16],[3,7,0.16],[3.5,12,0.14],[3.75,7,0.10]]
];
for (let bar = 0; bar < 24; bar++) {
  const start = 2 + bar * 2, section = Math.floor(bar / 4), ci = progression[bar], root = roots[ci], chord = chordNotes[ci];
  const breakdown = section === 2, full = section >= 3;
  const variation = bar % 4;
  for (let q = 0; q < 4; q++) {
    const at = start + q * BEAT;
    bed.kick(at, q === 0 ? 0.47 : 0.43);
    bed.hat(at, breakdown ? 0.012 : 0.020);
    if (!breakdown || q % 2 === 1) bed.hat(at + 0.25, full ? 0.055 : 0.036, q === 3 && variation % 2 === 1);
    if (q === 1 || q === 3) {
      bed.snare(at, breakdown ? 0.060 : full ? 0.18 : 0.12, section === 1);
      if (full) bed.clap(at + 0.006, 0.095);
    }
    if ((section === 1 || full) && (q + variation) % 2 === 0) {
      bed.hat(at + 0.375, full ? 0.024 : 0.018);
      bed.hat(at + 0.125, 0.012);
    }
    if (section === 4 && q % 2 === 0) bed.cymbal(at, 0.018, 0.27);
  }
  if (variation === 0 && section !== 2) bed.cymbal(start, full ? 0.085 : 0.045, 0.7);
  const bass = breakdown ? [[0,0,0.45],[2,0,0.4],[3.5,7,0.15]] : bassPatterns[(bar + section) % 4];
  for (const [offset, degree, length] of bass) bed.note(root - 12 + degree, start + offset * BEAT + 0.018, length, breakdown ? 0.14 : full ? 0.195 : 0.16, 'bass');
  // Every section uses a different voicing rhythm, not a cloned four-bar loop.
  if (breakdown) {
    for (const degree of chord) bed.note(root + 12 + degree, start + 0.045, 2.35, 0.023, 'pad');
    bed.note(root + 24 + chord[(variation + 1) % 4], start + 1.25, 0.65, 0.033, 'pluck', true);
  } else {
    const stabs = section === 0 ? [0.1,1.25] : section === 1 ? [0.25,0.875,1.5] : [0.06,0.75,1.375];
    for (const offset of stabs) for (let n = 0; n < 4; n++) bed.note(root + 12 + chord[n] + (section === 4 && n > 1 ? 12 : 0), start + offset + n * 0.003, section === 0 ? 0.55 : 0.25, section === 0 ? 0.023 : 0.028);
    const arpSteps = section === 0 && bar < 2 ? [3,7] : section === 1 ? [1,3,6] : section === 4 ? [0,2,3,5,7] : [1,3,5,6,7];
    for (let j = 0; j < arpSteps.length; j++) {
      const step = arpSteps[j], degree = chord[(j + variation + section) % 4];
      bed.note(root + 12 + degree + (section >= 4 && j % 3 === 2 ? 12 : 0), start + step * 0.25 + 0.032, 0.22, full ? 0.043 : 0.032, 'pluck', true);
    }
  }
  // Fills vary both placement and instrument across each four-bar phrase.
  if (variation === 3) {
    bed.tom(start + 1.5, 53 + section, breakdown ? 0.045 : 0.10);
    bed.tom(start + 1.75, 48 + section, breakdown ? 0.055 : 0.11);
    bed.snare(start + 1.875, full ? 0.12 : 0.07);
    bed.hat(start + 1.75, 0.075, true);
    if (section >= 3) bed.tom(start + 1.625, 57, 0.08);
  } else if (section === 5 && variation === 2) {
    bed.snare(start + 1.625, 0.07);
    bed.tom(start + 1.875, 50, 0.095);
  }
}
bed.cymbal(50, 0.075, 1.5);
for (const degree of [0,3,7,10]) bed.note(57 + degree, 50, 1.9, 0.045, 'pad');
bed.note(45, 50, 0.95, 0.17, 'bass');
for (let i = Math.round(51.2 * RATE); i < bed.data.length; i++) bed.data[i] *= Math.max(0, (52 - i / RATE) / 0.8);
save('bed', bed);

const melodyMidi = [76,81,72,77,79,84,74,79];
for (let index = 0; index < 8; index++) {
  const sound = renderer(0.225), frequency = hz(melodyMidi[index]);
  sound.event(0,0.225,t=>{
    const phase=TAU*frequency*t;
    return (Math.sin(phase+Math.sin(phase*2)*0.27*Math.exp(-t*30))*0.235+Math.sin(phase*2)*0.032*Math.exp(-t*45))*Math.exp(-t*15);
  },0);
  save('shot_'+index,sound);
}
const dash = renderer(0.225);
let low = 0;
dash.event(0,0.225,t=>{
  low=low*0.73+noise()*0.27;
  const phase=TAU*(201*t-155*t*t);
  return (Math.sin(phase)*0.225+Math.sin(phase*2)*0.055+low*0.15*(0.65+Math.cos(TAU*84*t)*0.35))*Math.exp(-t*22);
},0.0001);
save('dash',dash);

const beats = [...Array.from({length:96},(_,i)=>i),...metadata.extra_halfbeats].sort((a,b)=>a-b);
for (const beat of beats) {
  const ci=progression[Math.floor(beat/4)];
  const sampleIndex=ci*2+Math.round(beat)%2;
  const voice=Number.isInteger(beat)&&beat%16===15 ? 'dash' : 'shot';
  const sample=voice==='dash'?'dash.wav':'shot_'+sampleIndex+'.wav';
  const index=metadata.cues.length;
  metadata.cues.push({index,beat,time:2+beat*BEAT,type:'tap',voice,sample_index:sampleIndex,sample,stem_channel:index%2,stem_path:index%2?'response_odd.wav':'response_even.wav',note_duration:metadata.files[sample.replace('.wav','')].duration});
}
for (let channel=0;channel<2;channel++) {
  const buffer=wavHeader(LENGTH*RATE);
  for (const cue of metadata.cues.filter(c=>c.stem_channel===channel)) {
    const original=fs.readFileSync(path.join(OUT,cue.sample));
    original.copy(buffer,44+Math.round(cue.time*RATE)*2,44);
  }
  const name=channel?'response_odd':'response_even';
  fs.writeFileSync(path.join(OUT,name+'.wav'),buffer);
  metadata.files[name]={...stats(buffer),bit_exact_copy:true};
}

// Validate actual files and actual composed PCM, not only the source values.
let checks=0,totalBytes=0,comparedSamples=0;
const actualBed=fs.readFileSync(path.join(OUT,'bed.wav'));
for (const [name,info] of Object.entries(metadata.files)) {
  const b=fs.readFileSync(path.join(OUT,name+'.wav'));
  if(b.toString('ascii',0,4)!=='RIFF'||b.toString('ascii',8,12)!=='WAVE'||b.readUInt16LE(20)!==1||b.readUInt16LE(22)!==1||b.readUInt32LE(24)!==RATE||b.readUInt16LE(34)!==16)throw Error('PCM format '+name);
  if((b.length-44)/2!==info.frames||b.readUInt32LE(40)!==info.frames*2)throw Error('Frame count '+name);
  if(info.clipped_samples||info.peak>=0.9||Math.abs(info.dc_mean)>.001)throw Error('PCM integrity '+name);
  if(name.startsWith('shot_')||name==='dash')if(info.duration>.23||info.onset_ms>1)throw Error('Response onset/duration '+name);
  checks+=3;totalBytes+=b.length;
}
const responses=metadata.response_stems.paths.map(file=>fs.readFileSync(path.join(OUT,file)));
for (const cue of metadata.cues) {
  const original=fs.readFileSync(path.join(OUT,cue.sample)),response=responses[cue.stem_channel],start=Math.round(cue.time*RATE);
  for(let i=0;i<(original.length-44)/2;i++){
    if(original.readInt16LE(44+i*2)!==response.readInt16LE(44+(start+i)*2))throw Error('Response PCM mismatch '+cue.index);
    comparedSamples++;
  }
  if(cue.time+cue.note_duration>50)throw Error('Cue beyond battle');
}
checks+=metadata.cues.length;
const barHashes=[];
for(let bar=0;bar<24;bar++){
  const start=Math.round((2+bar*2)*RATE);
  barHashes.push(crypto.createHash('sha256').update(actualBed.subarray(44+start*2,44+(start+RATE*2)*2)).digest('hex'));
}
if(new Set(barHashes).size!==24)throw Error('Repeated complete bar PCM');
checks++;
const filtered=new Float64Array(LENGTH*RATE);
let filter=0;const alpha=1-Math.exp(-TAU*220/RATE);
for(let i=0;i<filtered.length;i++){filter+=alpha*(actualBed.readInt16LE(44+2*i)/32768-filter);filtered[i]=filter;}
function rms(time,length){const start=Math.round(time*RATE),n=Math.round(length*RATE);let sum=0;for(let i=start;i<start+n;i++)sum+=filtered[i]**2;return Math.sqrt(sum/n);}
const pulseRatios=Array.from({length:96},(_,beat)=>rms(2+beat*BEAT+.007,.068)/Math.max(.00001,rms(2+beat*BEAT+.17,.055)));
if(Math.min(...pulseRatios)<1.7)throw Error('Kick pulse obscured: '+Math.min(...pulseRatios));
checks++;
for(const section of metadata.sections){
  const start=Math.round(section.from*RATE),end=Math.round(section.to*RATE);let energy=0,peak=0;
  for(let i=start;i<end;i++){const value=actualBed.readInt16LE(44+i*2)/32768;energy+=value*value;peak=Math.max(peak,Math.abs(value));}
  section.actual_rms=+Math.sqrt(energy/(end-start)).toFixed(6);section.actual_peak=+peak.toFixed(6);
  section.pcm_sha256=crypto.createHash('sha256').update(actualBed.subarray(44+start*2,44+end*2)).digest('hex');
}
let combinedPeak=0;
for(let i=0;i<LENGTH*RATE;i++){
  let sample=actualBed.readInt16LE(44+i*2)/32768*10**(-3/20);
  for(const response of responses)sample+=response.readInt16LE(44+i*2)/32768*10**(-1/20);
  combinedPeak=Math.max(combinedPeak,Math.abs(sample));
}
if(combinedPeak>=.9)throw Error('Full response+bed mix clipping');
checks++;
const silentGaps=[0,1].map(channel=>{const cues=metadata.cues.filter(c=>c.stem_channel===channel);let gap=Infinity;for(let i=1;i<cues.length;i++)gap=Math.min(gap,cues[i].time-cues[i-1].time-cues[i-1].note_duration);return +gap.toFixed(6);});
if(metadata.cues.length!==102||silentGaps.some(gap=>gap<.27))throw Error('Stem gap/cue count');
checks++;
metadata.validation={checks,passed:true,total_wav_bytes:totalBytes,clipped_samples:0,unique_complete_bars:24,section_fingerprints_distinct:new Set(metadata.sections.map(s=>s.pcm_sha256)).size===metadata.sections.length,quarter_note_pulse_ratio_min:+Math.min(...pulseRatios).toFixed(3),quarter_note_pulse_ratio_average:+(pulseRatios.reduce((a,b)=>a+b)/96).toFixed(3),exact_response_cues:102,exact_response_samples_compared:comparedSamples,minimum_silent_gate_gap:silentGaps,actual_full_response_plus_bed_peak:+combinedPeak.toFixed(6)};
fs.writeFileSync(path.join(OUT,'metadata.json'),JSON.stringify(metadata,null,2)+'\n');
console.log(JSON.stringify({duration:LENGTH,frames:LENGTH*RATE,cues:metadata.cues.length,files:metadata.files,sections:metadata.sections.map(({id,from,to,actual_rms,actual_peak})=>({id,from,to,actual_rms,actual_peak})),validation:metadata.validation},null,2));
