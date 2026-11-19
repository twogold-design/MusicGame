'use strict';
// Four phase-aligned, original, seamless musical layers for the adventure game.
// Node.js standard library only. Every output is contained in this project.
const fs = require('node:fs');
const path = require('node:path');
const ROOT = path.resolve(__dirname, '..');
const OUT = path.join(ROOT, 'assets', 'audio', 'adventure');
const RATE = 22050;
const TAU = 2 * Math.PI;
const hz = midi => 440 * 2 ** ((midi - 69) / 12);
const layers = ['drums', 'bass', 'chords', 'melody'];
const songs = [
  { id: 'sunset', title: '落日汽水', bpm: 100, roots: [48, 53, 57, 55], chords: [[0,4,7,11],[0,4,7,11],[0,3,7,10],[0,4,7,10]], melody: [[0,-1,2,1,3,-1,2,-1],[1,2,3,-1,2,-1,1,-1],[2,-1,3,2,1,-1,0,1],[3,2,1,-1,2,1,0,-1]] },
  { id: 'neon', title: '霓虹夜行', bpm: 120, roots: [45, 53, 48, 55], chords: [[0,3,7,10],[0,4,7,11],[0,4,7,11],[0,4,7,10]], melody: [[0,2,-1,3,2,-1,1,2],[3,-1,2,1,0,1,2,-1],[0,1,2,-1,3,2,-1,1],[2,-1,1,0,1,2,3,-1]] },
  { id: 'cosmic', title: '星际派对', bpm: 140, roots: [50, 58, 53, 60], chords: [[0,3,7,10],[0,4,7,11],[0,4,7,11],[0,4,7,10]], melody: [[0,2,1,3,-1,2,3,1],[2,1,0,-1,3,2,1,2],[0,1,3,2,1,2,0,-1],[3,2,1,2,0,1,2,-1]] }
];

function createRenderer(frames, beat) {
  const buffers = Object.fromEntries(layers.map(name => [name, new Float64Array(frames)]));
  let randomState = 769483;
  const random = () => {
    randomState ^= randomState << 13; randomState ^= randomState >>> 17; randomState ^= randomState << 5;
    return (randomState >>> 0) / 2147483648 - 1;
  };
  // All event tails (and echo taps) wrap into the opening of the same loop.
  function event(layer, at, length, sample) {
    const start = Math.round(at * RATE), count = Math.ceil(length * RATE);
    for (let i = 0; i < count; i++) {
      const time = i / RATE;
      const edge = Math.min(1, time / 0.0015, (length - time) / 0.012);
      buffers[layer][(start + i) % frames] += sample(time) * Math.max(0, edge);
    }
  }
  function tone(layer, midi, at, length, amp, sound, echo = false) {
    const frequency = hz(midi);
    const shape = time => {
      const phase = TAU * frequency * time;
      const attack = Math.min(1, time / (sound === 'pad' ? 0.055 : 0.008));
      const decay = Math.exp(-time / (length * (sound === 'pad' ? 0.68 : 0.32)));
      let wave;
      if (sound === 'bass') wave = Math.sin(phase) * 0.9 + Math.sin(2 * phase) * 0.12 + Math.sin(3 * phase) * 0.04;
      else if (sound === 'pad') wave = Math.sin(phase) * 0.86 + Math.sin(phase * 2) * 0.12;
      else if (sound === 'bell') wave = Math.sin(phase + Math.sin(2 * phase) * Math.exp(-time * 14) * 0.55);
      else wave = Math.sin(phase) * 0.85 + Math.sin(phase * 2) * 0.12 + Math.sin(phase * 3) * 0.08 * Math.exp(-time * 12);
      return wave * amp * attack * decay;
    };
    event(layer, at, length, shape);
    if (echo) {
      event(layer, at + beat * 0.75, length, time => shape(time) * 0.14);
      event(layer, at + beat * 1.5, length, time => shape(time) * 0.035);
    }
  }
  function kick(at, strength = 1) {
    event('drums', at, 0.32, time => {
      const phase = TAU * (44 * time + 112 / 36 * (1 - Math.exp(-36 * time)));
      return Math.sin(phase) * Math.exp(-time * 18) * 0.245 * strength;
    });
  }
  function hat(at, open = false, strength = 1) {
    let previous = 0;
    const length = open ? 0.17 : 0.055;
    event('drums', at, length, time => {
      const next = random(), high = (next - previous * 0.9) * 0.53;
      previous = next;
      return high * Math.exp(-time / (length * 0.2)) * 0.038 * strength;
    });
  }
  function snare(at, strength = 1) {
    let previous = 0;
    event('drums', at, 0.19, time => {
      const next = random(), high = next - previous * 0.4;
      previous = next;
      const noise = high * Math.exp(-time * 29) * 0.07;
      const body = Math.sin(TAU * 185 * time) * Math.exp(-time * 45) * 0.03;
      return (noise + body) * strength;
    });
  }
  return { buffers, tone, kick, hat, snare };
}

function metrics(data) {
  let peak = 0, sum = 0, maxStep = 0;
  for (let i = 0; i < data.length; i++) {
    peak = Math.max(peak, Math.abs(data[i]));
    sum += data[i] * data[i];
    maxStep = Math.max(maxStep, Math.abs(data[i] - data[(i + data.length - 1) % data.length]));
  }
  return { peak: +peak.toFixed(6), rms: +Math.sqrt(sum / data.length).toFixed(6), boundary_step: +Math.abs(data[0] - data[data.length - 1]).toFixed(6), max_sample_step: +maxStep.toFixed(6) };
}

function wav(data) {
  const buffer = Buffer.alloc(44 + data.length * 2);
  buffer.write('RIFF',0); buffer.writeUInt32LE(buffer.length-8,4); buffer.write('WAVE',8);
  buffer.write('fmt ',12); buffer.writeUInt32LE(16,16); buffer.writeUInt16LE(1,20); buffer.writeUInt16LE(1,22);
  buffer.writeUInt32LE(RATE,24); buffer.writeUInt32LE(RATE*2,28); buffer.writeUInt16LE(2,32); buffer.writeUInt16LE(16,34);
  buffer.write('data',36); buffer.writeUInt32LE(data.length*2,40);
  for (let i=0;i<data.length;i++) {
    if (Math.abs(data[i]) >= 1) throw Error('Clipping: output violates fixed mix headroom');
    buffer.writeInt16LE(Math.round(data[i]*32767),44+i*2);
  }
  return buffer;
}

fs.mkdirSync(OUT,{recursive:true});
const metadata = { sample_rate: RATE, bit_depth: 16, channels: 1, beats_per_loop: 16, gain_policy: 'All layers at 0 dB; master at -3 dB recommended; no layer normalization.', tracks: [] };
for (const song of songs) {
  const beat=60/song.bpm, frames=Math.round(16*beat*RATE);
  const renderer=createRenderer(frames,beat);
  const {buffers,tone,kick,hat,snare}=renderer;
  for (let bar=0;bar<4;bar++) {
    const root=song.roots[bar], chord=song.chords[bar], beginning=bar*4*beat;
    // The harmony layer includes a soft pad and offbeat chord taps.
    for (let n=0;n<4;n++) tone('chords',root+12+chord[n],beginning+n*0.007,beat*4.7,0.025,'pad');
    for (let step=0;step<8;step++) {
      const at=beginning+step*beat/2;
      if (step%2===0) {
        kick(at, step===0 ? 1 : 0.88);
        tone('bass',root-12+(step===6 ? 7 : 0),at+0.006,beat*0.85,0.18,'bass');
      }
      if (step===2 || step===6) snare(at);
      hat(at,step===7 && bar%2===1,step%2 ? 0.95 : 0.5);
      if (step===3 || step===7) {
        for (let n=0;n<3;n++) tone('chords',root+12+chord[n],at,beat*0.3,0.014,'lead');
      }
      const degree=song.melody[bar][step];
      if (degree>=0) tone('melody',root+24+chord[degree],at,beat*(step===6 ? 0.95 : 0.68),0.105,song.id==='sunset' ? 'bell' : 'lead',true);
      if (song.id==='cosmic' && step===7 && bar===3) snare(at+beat*0.25,0.35);
    }
  }
  const track={id:song.id,title:song.title,bpm:song.bpm,frames,duration:frames/RATE,files:{}};
  const mixed=new Float64Array(frames);
  let peakBound=0;
  for (const layer of layers) {
    const data=buffers[layer], stats=metrics(data), filename=song.id+'_'+layer+'.wav';
    peakBound+=stats.peak;
    for (let i=0;i<frames;i++) mixed[i]+=data[i];
    const bytes=wav(data);
    fs.writeFileSync(path.join(OUT,filename),bytes);
    track.files[layer]={filename,bytes:bytes.length,...stats};
    // Boundary jumps should be far below an audible DC-style click.
    if (stats.boundary_step>0.03) throw Error(filename+': boundary discontinuity too large');
  }
  track.mix=metrics(mixed);
  track.sum_of_layer_peaks=+peakBound.toFixed(6);
  if (peakBound>=0.9 || track.mix.peak>=0.9) throw Error('Insufficient fixed-mix headroom');
  metadata.tracks.push(track);
  console.log(JSON.stringify(track));
}
fs.writeFileSync(path.join(OUT,'metadata.json'),JSON.stringify(metadata,null,2)+'\n');

const rows=metadata.tracks.map(t=>`| ${t.title} / ${t.id} | ${t.bpm} | ${t.frames} | ${t.duration.toFixed(9)} | ${t.mix.peak.toFixed(4)} | ${t.sum_of_layer_peaks.toFixed(4)} |`).join('\n');
const details=metadata.tracks.map(t=>`### ${t.title}\n\n| 声部 | 峰值 | RMS | 循环边界相邻样本差 |\n| --- | --- | --- | --- |\n`+layers.map(l=>{const s=t.files[l];return `| ${l} | ${s.peak.toFixed(5)} | ${s.rms.toFixed(5)} | ${s.boundary_step.toFixed(6)} |`;}).join('\n')).join('\n\n');
const doc=`# 节拍冒险：四层循环音乐

本目录全部声部由项目原创合成，无外部歌曲、采样或依赖。执行 \`node tools/generate_adventure_audio.cjs\` 可重建12个WAV及机器可读 \`assets/audio/adventure/metadata.json\`。

全部WAV均为 **22050 Hz、16位PCM、单声道、精确16拍（四小节）**。无准备音、无倒数、无尾部空白。相同曲目的四个文件帧数完全一致，首拍均在第0秒；最后一小节的包络与回声尾音按总帧数回卷叠加到开头，避免切断尾音。它们是同一首循环的四条声轨，必须保持同一个播放相位。

| 曲目 | BPM | 帧数 | 循环秒数 | 四层合奏峰值 | 各层峰值之和上界 |
| --- | --- | --- | --- | --- | --- |
${rows}

## 声部分工与推荐混音

- \`{id}_drums.wav\`：底鼓、拍手式军鼓、踩镲；初始可听的节拍。
- \`{id}_bass.wav\`：根音与五度低音，增加推进感。
- \`{id}_chords.wav\`：四小节和声、柔和垫音与反拍和弦。
- \`{id}_melody.wav\`：可辨识主旋律及轻量节拍回声，完成后形成完整歌曲。

建议四个AudioStreamPlayer在同一帧从0秒开始播放，并设置所有流循环开始帧为0、结束帧为表中帧数。鼓层音量0 dB，其余层初始静音但仍持续播放；交付时渐变至0 dB，从而不改变相位。推荐0.12–0.20秒音量淡入，避免在波形非零处硬切；不要解锁时才从0重新播放某一层。播放期间所有层共用同一个暂停/恢复操作。

各层已采用固定配比，**不要分别做峰值归一化**。四层各0 dB时，峰值之和仍低于0.9；实际同相位合奏峰值更低。推荐音乐母线另设−3 dB，为游戏音效留余量。若Web导出采用采样播放，务必实际验证循环标记；如采用AudioStreamWAV资源，设置loop_mode为LOOP_FORWARD、loop_begin=0、loop_end=对应frames。声部解锁过程中改变音量即可。

## 数值验证

生成器验证了三套曲目各层帧数完全一致、PCM无削波、各层峰值和小于0.9、循环边界相邻采样差小于0.03。边界差是正常音频波形相邻采样的变化量，不要求首末采样恰好相同。包络尾音回卷确保所有事件在循环接缝处保持连续。

${details}
`;
fs.mkdirSync(path.join(ROOT,'docs'),{recursive:true});
fs.writeFileSync(path.join(ROOT,'docs','adventure-audio.md'),doc);
