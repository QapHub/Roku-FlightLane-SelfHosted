import zlib from "node:zlib";

const CRC_TABLE = (() => {
  const table = new Uint32Array(256);
  for (let n = 0; n < 256; n += 1) {
    let c = n;
    for (let k = 0; k < 8; k += 1) {
      c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    }
    table[n] = c >>> 0;
  }
  return table;
})();

export function crc32(buffer, previous = 0) {
  let crc = ~previous >>> 0;
  for (let index = 0; index < buffer.length; index += 1) {
    crc = CRC_TABLE[(crc ^ buffer[index]) & 0xff] ^ (crc >>> 8);
  }
  return ~crc >>> 0;
}

function pngChunk(type, data) {
  const length = Buffer.alloc(4);
  length.writeUInt32BE(data.length);
  const typeAndData = Buffer.concat([Buffer.from(type, "ascii"), data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(typeAndData));
  return Buffer.concat([length, typeAndData, crc]);
}

// Encodes straight (non-premultiplied) RGBA pixels as a PNG.
export function encodePng(width, height, rgba) {
  const header = Buffer.alloc(13);
  header.writeUInt32BE(width, 0);
  header.writeUInt32BE(height, 4);
  header[8] = 8;
  header[9] = 6;
  const stride = width * 4;
  const raw = Buffer.alloc((stride + 1) * height);
  for (let y = 0; y < height; y += 1) {
    raw[y * (stride + 1)] = 0;
    rgba.copy(raw, y * (stride + 1) + 1, y * stride, (y + 1) * stride);
  }
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    pngChunk("IHDR", header),
    pngChunk("IDAT", zlib.deflateSync(raw, { level: 9 })),
    pngChunk("IEND", Buffer.alloc(0)),
  ]);
}

class Canvas {
  constructor(width, height) {
    this.width = width;
    this.height = height;
    this.pixels = Buffer.alloc(width * height * 4);
  }

  // Composites a straight-alpha color over the pixel with the given coverage.
  blend(x, y, [red, green, blue, alpha], coverage) {
    const sourceAlpha = (alpha / 255) * coverage;
    if (sourceAlpha <= 0) return;
    const offset = (y * this.width + x) * 4;
    const destinationAlpha = this.pixels[offset + 3] / 255;
    const outAlpha = sourceAlpha + destinationAlpha * (1 - sourceAlpha);
    const mix = (source, destination) =>
      Math.round(
        (source * sourceAlpha + destination * destinationAlpha * (1 - sourceAlpha)) / outAlpha,
      );
    this.pixels[offset] = mix(red, this.pixels[offset]);
    this.pixels[offset + 1] = mix(green, this.pixels[offset + 1]);
    this.pixels[offset + 2] = mix(blue, this.pixels[offset + 2]);
    this.pixels[offset + 3] = Math.round(outAlpha * 255);
  }

  // Antialiased stroke of any shape described by a distance-to-centerline function.
  stroke(bounds, distance, color, width) {
    const half = width / 2;
    const minX = Math.max(0, Math.floor(bounds.minX - half - 1));
    const maxX = Math.min(this.width - 1, Math.ceil(bounds.maxX + half + 1));
    const minY = Math.max(0, Math.floor(bounds.minY - half - 1));
    const maxY = Math.min(this.height - 1, Math.ceil(bounds.maxY + half + 1));
    for (let y = minY; y <= maxY; y += 1) {
      for (let x = minX; x <= maxX; x += 1) {
        const coverage = Math.min(1, Math.max(0, half + 0.5 - distance(x + 0.5, y + 0.5)));
        this.blend(x, y, color, coverage);
      }
    }
  }

  line(x1, y1, x2, y2, color, width) {
    const dx = x2 - x1;
    const dy = y2 - y1;
    const lengthSquared = dx * dx + dy * dy;
    this.stroke(
      {
        minX: Math.min(x1, x2),
        maxX: Math.max(x1, x2),
        minY: Math.min(y1, y2),
        maxY: Math.max(y1, y2),
      },
      (px, py) => {
        const t = lengthSquared
          ? Math.min(1, Math.max(0, ((px - x1) * dx + (py - y1) * dy) / lengthSquared))
          : 0;
        return Math.hypot(px - (x1 + t * dx), py - (y1 + t * dy));
      },
      color,
      width,
    );
  }

  circle(cx, cy, radius, color, width) {
    this.stroke(
      { minX: cx - radius, maxX: cx + radius, minY: cy - radius, maxY: cy + radius },
      (px, py) => Math.abs(Math.hypot(px - cx, py - cy) - radius),
      color,
      width,
    );
  }
}

export function createRadarPng(outerRadius, size = 840) {
  const canvas = new Canvas(size, size);
  const minor = [125, 211, 252, 115];
  const major = [56, 189, 248, 205];
  const cross = [186, 230, 253, 100];
  const center = size / 2;
  canvas.line(center, center - outerRadius, center, center + outerRadius, cross, 2);
  canvas.line(center - outerRadius, center, center + outerRadius, center, cross, 2);
  for (const fraction of [0.25, 0.5, 0.75, 1.0]) {
    canvas.circle(center, center, outerRadius * fraction, fraction === 1 ? major : minor, fraction === 1 ? 3 : 2);
  }
  return encodePng(size, size, canvas.pixels);
}

class BitWriter {
  constructor() {
    this.bytes = [];
    this.buffer = 0;
    this.count = 0;
  }

  write(code, length) {
    for (let bit = length - 1; bit >= 0; bit -= 1) {
      this.buffer = (this.buffer << 1) | ((code >> bit) & 1);
      this.count += 1;
      if (this.count === 8) {
        this.bytes.push(this.buffer);
        if (this.buffer === 0xff) this.bytes.push(0x00);
        this.buffer = 0;
        this.count = 0;
      }
    }
  }

  flush() {
    while (this.count !== 0) this.write(1, 1);
    return Buffer.from(this.bytes);
  }
}

function huffmanCodes(bits, values) {
  const codes = new Map();
  let code = 0;
  let valueIndex = 0;
  for (let length = 1; length <= 16; length += 1) {
    for (let count = 0; count < bits[length - 1]; count += 1) {
      codes.set(values[valueIndex], { code, length });
      valueIndex += 1;
      code += 1;
    }
    code <<= 1;
  }
  return codes;
}

function jpegSegment(marker, payload) {
  const header = Buffer.alloc(4);
  header.writeUInt16BE(marker, 0);
  header.writeUInt16BE(payload.length + 2, 2);
  return Buffer.concat([header, payload]);
}

// Encodes a baseline JPEG filled with one color. Every 8x8 block is flat, so only DC
// coefficients are needed: the standard DC table plus an AC table holding just EOB.
export function createSolidJpeg(width, height, [red, green, blue]) {
  const dcBits = [0, 1, 5, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0];
  const dcValues = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11];
  const acBits = [1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
  const acValues = [0x00];
  const dcCodes = huffmanCodes(dcBits, dcValues);
  const eob = huffmanCodes(acBits, acValues).get(0x00);

  const components = [
    0.299 * red + 0.587 * green + 0.114 * blue,
    128 - 0.168736 * red - 0.331264 * green + 0.5 * blue,
    128 + 0.5 * red - 0.418688 * green - 0.081312 * blue,
  ].map((value) => Math.round(8 * (value - 128)));

  const writer = new BitWriter();
  const predictors = [0, 0, 0];
  const blockCount = Math.ceil(width / 8) * Math.ceil(height / 8);
  for (let block = 0; block < blockCount; block += 1) {
    components.forEach((dc, index) => {
      const difference = dc - predictors[index];
      predictors[index] = dc;
      const magnitude = Math.abs(difference);
      const category = magnitude === 0 ? 0 : Math.floor(Math.log2(magnitude)) + 1;
      const { code, length } = dcCodes.get(category);
      writer.write(code, length);
      if (category > 0) {
        writer.write(difference > 0 ? difference : difference + (1 << category) - 1, category);
      }
      writer.write(eob.code, eob.length);
    });
  }

  const quantization = Buffer.alloc(65, 1);
  quantization[0] = 0x00;
  const frame = Buffer.from([
    8,
    height >> 8,
    height & 0xff,
    width >> 8,
    width & 0xff,
    3,
    1, 0x11, 0,
    2, 0x11, 0,
    3, 0x11, 0,
  ]);
  const huffman = Buffer.concat([
    Buffer.from([0x00, ...dcBits, ...dcValues]),
    Buffer.from([0x10, ...acBits, ...acValues]),
  ]);
  const scan = Buffer.from([3, 1, 0x00, 2, 0x00, 3, 0x00, 0, 63, 0]);
  const jfif = Buffer.from([0x4a, 0x46, 0x49, 0x46, 0x00, 1, 1, 0, 0, 1, 0, 1, 0, 0]);

  return Buffer.concat([
    Buffer.from([0xff, 0xd8]),
    jpegSegment(0xffe0, jfif),
    jpegSegment(0xffdb, quantization),
    jpegSegment(0xffc0, frame),
    jpegSegment(0xffc4, huffman),
    jpegSegment(0xffda, scan),
    writer.flush(),
    Buffer.from([0xff, 0xd9]),
  ]);
}
