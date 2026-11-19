'use strict';
// Original material impacts: dependency-free deterministic synthesis.
// Every output lives in assets/audio/demolition; no existing resources touched.
const fs = require('node:fs');
const path = require('node:path');
const ROOT = path.resolve(__dirname, '..');
const OUT = path.join(ROOT, 'assets', 'audio', 'demolition');
const RATE = 22050, TAU = 2 * Math.PI;
let randomState = 735971;
function random() {
  randomState ^= randomState << 13; randomState ^= randomState >>> 17; randomState ^= randomState << 5;
  return (randomState >>> 0) / 2147483648 - 1;
}
function create(seconds) {
  const data = new Float64Array(Math.round(seconds * RATE));
  function event(at, length, shape) {
    const start = Math.round(at * RATE), count = Math.ceil(length * RATE);
    for (let i = 0; i < count && start + i < data.length; i++) {
      const t = i / RATE;
      const fade = Math.max(0, Math.min(1, t / 0.00025, (length - t) / 0.009));
      data[start + i] += shape(t) * fade;
    }
  }
  function mode(frequency, at, length, amp, decay, phase = 0) {
    event(at, length, t => Math.sin(TAU * frequency * t + phase) * Math.exp(-t * decay) * amp);
  }
  function crack(at, length, amp, damping, brightness = 0.7) {
    let smooth = 0, previous = 0;
    event(at, length, t => {
      const next = random();
      smooth = smooth * brightness + next * (1 - brightness);
      const value = smooth - previous * 0.3;
      previous = smooth;
      return value * Math.exp(-t * damping) * amp;
    });
  }
  return { data, event, mode, crack };
}
function encode(data) {
  const buffer = Buffer.alloc(44 + data.length * 2);
  buffer.write('RIFF', 0); buffer.writeUInt32LE(buffer.length - 8, 4); buffer.write('WAVE', 8);
  buffer.write('fmt ', 12); buffer.writeUInt32LE(16, 16); buffer.writeUInt16LE(1, 20); buffer.writeUInt16LE(1, 22);
  buffer.writeUInt32LE(RATE, 24); buffer.writeUInt32LE(RATE * 2, 28); buffer.writeUInt16LE(2, 32); buffer.writeUInt16LE(16, 34);
  buffer.write('data', 36); buffer.writeUInt32LE(data.length * 2, 40);
  // Fixed gain, 35Hz high-pass and mild saturation preserve material balance.
  const coefficient = Math.exp(-TAU * 35 / RATE);
  let previousIn = 0, previousOut = 0;
  for (let i = 0; i < data.length; i++) {
    const filtered = coefficient * (previousOut + data[i] - previousIn);
    previousIn = data[i]; previousOut = filtered;
    const fade = Math.min(1, (data.length - 1 - i) / (RATE * 0.009));
    buffer.writeInt16LE(Math.round(Math.tanh(filtered * 1.3) * 0.72 * Math.max(0, fade) * 32767), 44 + i * 2);
  }
  return buffer;
}

fs.mkdirSync(OUT, { recursive: true });
const wood = create(0.19);
// A dry low knock immediately splits into several irregular cracks.
for (const [frequency, amp] of [[162,0.26],[291,0.17],[487,0.09]]) wood.mode(frequency,0,0.15,amp,40);
wood.crack(0,0.043,0.38,85,0.30);
wood.crack(0.013,0.052,0.24,66,0.40);
wood.crack(0.037,0.064,0.17,55,0.46);
wood.crack(0.071,0.075,0.09,49,0.50);
const glass = create(0.24);
// Inharmonic shard resonances, band-limited to avoid a piercing hiss.
glass.crack(0,0.035,0.24,100,0.32);
for (const [frequency, amp, decay] of [[1237,0.11,35],[1841,0.095,32],[2497,0.07,41],[3211,0.04,51]]) glass.mode(frequency,0,0.18,amp,decay);
for (const [at, frequency, amp] of [[0.022,1613,0.09],[0.047,2111,0.075],[0.081,1399,0.065],[0.116,2677,0.042],[0.153,1811,0.027]]) {
  glass.mode(frequency,at,0.07,amp,60);
  glass.crack(at,0.037,amp*0.7,90,0.45);
}
const metal = create(0.27);
metal.crack(0,0.027,0.18,110,0.47);
for (const [frequency, amp, decay] of [[237,0.22,24],[569,0.13,20],[1013,0.08,25],[1481,0.045,33],[2137,0.023,45]]) metal.mode(frequency,0,0.255,amp,decay);
metal.mode(723,0.042,0.17,0.035,29);
const thump = create(0.18);
thump.event(0,0.17,t=>{
  const phase=TAU*(72*t+72/45*(1-Math.exp(-45*t)));
  return (Math.sin(phase)*0.43+Math.sin(phase*2)*0.11)*Math.exp(-t*29);
});
thump.mode(302,0,0.065,0.095,70);
thump.crack(0,0.028,0.15,115,0.58);
// Cartoony palm slap: a crisp broadband clap and a short warm hand/body pop.
// Added after the original four sounds so their seeded waveforms stay intact.
const slap = create(0.135);
slap.crack(0,0.052,0.42,82,0.31);
slap.mode(367,0,0.092,0.20,51);
slap.mode(911,0,0.055,0.065,88);
slap.crack(0.008,0.039,0.17,110,0.38);
slap.mode(183,0.004,0.11,0.09,54);

const metadata = { sample_rate: RATE, bit_depth: 16, channels: 1, highpass_hz: 35,
  mixing: 'Material effects at -5 dB recommended under bed.wav (-3 dB). Keep rhythmic player melody audible. Use one material impact per strike, with optional thump only for a large smash. Avoid stacking all material effects for every fragment.',
  descriptions: { wood: 'Dry board split: low hollow knock and irregular cracks.', glass: 'Clear small glass shard cascade with restrained high frequencies.', metal: 'Dense metal clang with short inharmonic ringing.', thump: 'Heavy close impact with audible low-mid punch, no long sub tail.', slap: 'Cartoony palm slap: crisp dry clap with a warm short pop, no long hiss.' }, files: {}, validation: {} };
let totalBytes = 0, checks = 0;
for (const [name,sound] of Object.entries({wood,glass,metal,thump,slap})) {
  const buffer = encode(sound.data);
  const filename = path.join(OUT,name+'.wav');
  fs.writeFileSync(filename,buffer);
  const actual = fs.readFileSync(filename);
  if (actual.toString('ascii',0,4)!=='RIFF'||actual.toString('ascii',8,12)!=='WAVE'||actual.readUInt16LE(20)!==1||actual.readUInt16LE(22)!==1||actual.readUInt32LE(24)!==RATE||actual.readUInt16LE(34)!==16) throw Error('PCM format');
  let peak=0,energy=0,dc=0,clipped=0,first=-1;
  const frames=(actual.length-44)/2;
  for(let i=0;i<frames;i++) {
    const pcm=actual.readInt16LE(44+2*i), sample=pcm/32768;
    peak=Math.max(peak,Math.abs(sample));energy+=sample**2;dc+=sample;
    if(Math.abs(pcm)>=32767)clipped++;
    if(first<0&&Math.abs(sample)>.001)first=i;
  }
  if(clipped||peak>.72||first>22||Math.abs(dc/frames)>.002||actual.readInt16LE(actual.length-2)!==0)throw Error('PCM integrity: '+name);
  metadata.files[name]={frames,duration:frames/RATE,bytes:actual.length,peak:+peak.toFixed(6),rms:+Math.sqrt(energy/frames).toFixed(6),onset_ms:+(first/RATE*1000).toFixed(4),dc_mean:+(dc/frames).toFixed(8),clipped_samples:clipped};
  totalBytes+=actual.length;checks+=3;
}
metadata.validation={checks,passed:true,total_wav_bytes:totalBytes,clipped_samples:0};
fs.writeFileSync(path.join(OUT,'metadata.json'),JSON.stringify(metadata,null,2)+'\n');
console.log(JSON.stringify(metadata,null,2));
