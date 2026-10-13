import { expect, test } from 'bun:test';
import { readFileSync } from 'node:fs';

type TProcessor = {
  inputBuf: Float32Array;
  inputBufIdx: number;
  isModuleReady: boolean;
  outputBuf: Float32Array;
  outputBufIdx: number;
  outputAvailable: number;
  process(
    inputs: Float32Array[][],
    outputs: Float32Array[][],
    parameters: { mix: Float32Array }
  ): boolean;
};

const processorSource = readFileSync(
  new URL('../../public/rnnoise/rnnoise-worklet-processor.js', import.meta.url),
  'utf8'
);

const loadProcessor = () => {
  let processorType: (new () => TProcessor) | undefined;
  const registerProcessor = (_name: string, type: new () => TProcessor) => {
    processorType = type;
  };
  const defineProcessor = new Function(
    'AudioWorkletProcessor',
    'sampleRate',
    'registerProcessor',
    processorSource
  );

  defineProcessor(class {}, 48000, registerProcessor);

  if (!processorType) {
    throw new Error('RNNoise AudioWorklet processor did not register.');
  }

  return Object.create(processorType.prototype) as TProcessor;
};

test('RNNoise worklet mixes raw and processed samples at the selected amount', () => {
  const processor = loadProcessor();
  const input = new Float32Array(128).fill(0.2);
  const output = new Float32Array(128);
  processor.isModuleReady = true;
  processor.inputBuf = new Float32Array(480);
  processor.inputBufIdx = 0;
  processor.outputBuf = new Float32Array(480).fill(0.6);
  processor.outputBufIdx = 0;
  processor.outputAvailable = 128;

  processor.process([[input]], [[output]], {
    mix: new Float32Array(128).fill(0.5)
  });

  expect(output[0]).toBeCloseTo(0.4);
  expect(output[127]).toBeCloseTo(0.4);
});

test('RNNoise worklet bypasses processing when the mix is zero', () => {
  const processor = loadProcessor();
  const input = new Float32Array(128).fill(0.2);
  const output = new Float32Array(128);

  processor.process([[input]], [[output]], {
    mix: new Float32Array(128).fill(0)
  });

  expect(output).toEqual(input);
});
