/*
 * format - haXe File Formats
 *
 *  JPG File Format
 *
 * Copyright 2014 Mozilla Foundation
 *
 * Licensed under the Apache License, Version 2.0 (the 'License');
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an 'AS IS' BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * This code was forked from https://github.com/notmasteryet/jpgjs. The original
 * version was created by github user notmasteryet
 *
 * - The JPEG specification can be found in the ITU CCITT Recommendation T.81
 *  (www.w3.org/Graphics/JPEG/itu-t81.pdf)
 * - The JFIF specification can be found in the JPEG File Interchange Format
 *  (www.w3.org/Graphics/JPEG/jfif3.pdf)
 * - The Adobe Application-Specific JPEG markers in the Supporting the DCT Filters
 *  in PostScript Level 2, Technical Note #5116
 *  (partners.adobe.com/public/developer/en/ps/sdk/5116.DCT_Filter.pdf)
 *
 * Copyright (c) 2015 Sven Otto (nensanders), jpgjs to haxe port based on https://github.com/mozilla/pdf.js
 *
 * Copyright (c) 2015, The haXe Project Contributors
 * All rights reserved.
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 *   - Redistributions of source code must retain the above copyright
 *     notice, this list of conditions and the following disclaimer.
 *   - Redistributions in binary form must reproduce the above copyright
 *     notice, this list of conditions and the following disclaimer in the
 *     documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE HAXE PROJECT CONTRIBUTORS "AS IS" AND ANY
 * EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL THE HAXE PROJECT CONTRIBUTORS BE LIABLE FOR
 * ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 * SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
 * CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH
 * DAMAGE.
 */

package format.jpg;

import Type.ValueType;
import haxe.ds.Vector;
import format.jpg.Data.Jfif;
import format.jpg.Data.Adobe;
import format.jpg.Data.Frame;
import format.jpg.Data.Component;
import format.jpg.Data.HuffNode;
import haxe.io.Bytes;

using haxe.io.Bytes;

@:access(haxe.io.Bytes)
class Reader {

    static var dctZigZag: Vector<Int>;

    inline static var dctCos1  =  4017;   // cos(pi/16)
    inline static var dctSin1  =   799;   // sin(pi/16)
    inline static var dctCos3  =  3406;   // cos(3*pi/16)
    inline static var dctSin3  =  2276;   // sin(3*pi/16)
    inline static var dctCos6  =  1567;   // cos(6*pi/16)
    inline static var dctSin6  =  3784;   // sin(6*pi/16)
    inline static var dctSqrt2 =  5793;   // sqrt(2)
    inline static var dctSqrt1d2 = 2896;  // sqrt(2) / 2

    var data : haxe.io.Bytes;

    public var width: Int;
    public var height: Int;

    var jfif: Jfif;
    var adobe: Adobe;
    var components: Array<Component>;
    public var numComponents: Int;

    public function new(i: haxe.io.Bytes) {
      //  i.bigEndian = true; // TODO check
        this.data = i; // For now we convert to pure bytes
        initZigZag();
    }

    private function initZigZag(): Void
    {
        dctZigZag = Vector.fromArrayCopy([
         0,
         1,  8,
        16,  9,  2,
         3, 10, 17, 24,
        32, 25, 18, 11, 4,
         5, 12, 19, 26, 33, 40,
        48, 41, 34, 27, 20, 13,  6,
         7, 14, 21, 28, 35, 42, 49, 56,
        57, 50, 43, 36, 29, 22, 15,
        23, 30, 37, 44, 51, 58,
        59, 52, 45, 38, 31,
        39, 46, 53, 60,
        61, 54, 47,
        55, 62,
        63
        ]);
    }

    public function getData(width: Int, height: Int, forceRGBoutput: Bool): haxe.io.Bytes
    {
        if (this.numComponents > 4) {
            throw 'Unsupported color mode';
        }
        // type of data: Uint8Array(width * height * numComponents)
        var data: haxe.io.Bytes = getLinearizedBlockData(width, height);

        if (this.numComponents == 3) {
            return convertYccToRgb(data);
        } else if (this.numComponents == 4) {
            if (isColorConversionNeeded()) {
                if (forceRGBoutput) {
                    return convertYcckToRgb(data);
                } else {
                    return convertYcckToCmyk(data);
                }
            } else if (forceRGBoutput) {
                return convertCmykToRgb(data);
            }
        }
        return data;
    }

    function getLinearizedBlockData(width: Int, height: Int): haxe.io.Bytes
    {
        var scaleX: Float = this.width / width;
        var scaleY: Float = this.height / height;

        var component: Component;
        var componentScaleX: Float;
        var componentScaleY: Float;
        var blocksPerScanline;
        var x, y, i, j, k;
        var index: Int = 0;
        var offset: Int = 0;
        var output: haxe.ds.Vector<Int>;
        var numComponents = this.components.length;
        var dataLength = width * height * numComponents;
        var data: haxe.io.Bytes = haxe.io.Bytes.alloc(dataLength);  // Uint8Array(dataLength);
        var xScaleBlockOffset: Vector<Int> = new Vector(width);
        var mask3LSB = 0xfffffff8; // used to clear the 3 LSBs

        for (i in 0...numComponents)
        {
            component = this.components[i];
            componentScaleX = component.scaleX * scaleX;
            componentScaleY = component.scaleY * scaleY;
            offset = i;
            output = component.output;
            blocksPerScanline = (component.blocksPerLine + 1) << 3;

            // precalculate the xScaleBlockOffset
            for (x in 0...width)
            {
                j = 0 | Std.int(x * componentScaleX);
                xScaleBlockOffset[x] = ((j & mask3LSB) << 3) | (j & 7);
            }

            // linearize the blocks of the component
            for (y in 0...height)
            {
                j = 0 | Std.int(y * componentScaleY);
                index = blocksPerScanline * (j & mask3LSB) | ((j & 7) << 3);

                for (x in 0...width)
                {
                    data.set(offset, output.get(index + xScaleBlockOffset[x]));
                    offset += numComponents;
                }
            }
        }
        return data;
    }

    function clamp0to255(a: Float): Int
    {
        return a <= 0.0 ? 0 : a >= 255.0 ? 255 : Std.int(a);
    }

    function isColorConversionNeeded()
    {
        if (this.adobe != null && this.adobe.transformCode != 0) {
            // The adobe transform marker overrides any previous setting
            return true;
        } else if (this.numComponents == 3) {
            return true;
        } else {
            return false;
        }
    }

    inline static function njClip(x: Int): Int
    {
        return x < 0 ? 0 : x > 0xFF ? 0xFF : x;
    }

    function convertYccToRgb(data: haxe.io.Bytes): haxe.io.Bytes
    {
        var y: Int;
        var cb: Int;
        var cr: Int;
        var i = 0;
        var length = data.length;
        while (i < length)
        {
            y = data.b.fastGet(i) << 8;
            cb = data.b.fastGet(i + 1) - 128;
            cr = data.b.fastGet(i + 2) - 128;
            var r = njClip((y + 359 * cr + 128) >> 8);
            var g = njClip((y -  88 * cb - 183 * cr + 128) >> 8);
            var b = njClip((y + 454 * cb + 128) >> 8);
            data.set(i    , r);
            data.set(i + 1, g);
            data.set(i + 2, b);
            i += 3;
        }
        return data;
    }

    function convertYcckToRgb(data: haxe.io.Bytes): haxe.io.Bytes
    {
        var Y: Float;
        var Cb: Float;
        var Cr: Float;
        var k: Float;
        var offset = 0;

        var i = 0;
        var length = data.length;
        while (i < length)
        {
            Y = data.b.fastGet(i);
            Cb = data.b.fastGet(i + 1);
            Cr = data.b.fastGet(i + 2);
            k = data.b.fastGet(i + 3);

            var r = -122.67195406894 +
            Cb * (-6.60635669420364e-5 * Cb + 0.000437130475926232 * Cr -
            5.4080610064599e-5 * Y + 0.00048449797120281 * k -
            0.154362151871126) +
            Cr * (-0.000957964378445773 * Cr + 0.000817076911346625 * Y -
            0.00477271405408747 * k + 1.53380253221734) +
            Y * (0.000961250184130688 * Y - 0.00266257332283933 * k +
            0.48357088451265) +
            k * (-0.000336197177618394 * k + 0.484791561490776);

            var g = 107.268039397724 +
            Cb * (2.19927104525741e-5 * Cb - 0.000640992018297945 * Cr +
            0.000659397001245577 * Y + 0.000426105652938837 * k -
            0.176491792462875) +
            Cr * (-0.000778269941513683 * Cr + 0.00130872261408275 * Y +
            0.000770482631801132 * k - 0.151051492775562) +
            Y * (0.00126935368114843 * Y - 0.00265090189010898 * k +
            0.25802910206845) +
            k * (-0.000318913117588328 * k - 0.213742400323665);

            var b = -20.810012546947 +
            Cb * (-0.000570115196973677 * Cb - 2.63409051004589e-5 * Cr +
            0.0020741088115012 * Y - 0.00288260236853442 * k +
            0.814272968359295) +
            Cr * (-1.53496057440975e-5 * Cr - 0.000132689043961446 * Y +
            0.000560833691242812 * k - 0.195152027534049) +
            Y * (0.00174418132927582 * Y - 0.00255243321439347 * k +
            0.116935020465145) +
            k * (-0.000343531996510555 * k + 0.24165260232407);

            data.set(offset++, clamp0to255(r));
            data.set(offset++, clamp0to255(g));
            data.set(offset++, clamp0to255(b));

            i += 4;
        }
        return data;
    }

    function convertYcckToCmyk(data: haxe.io.Bytes): haxe.io.Bytes
    {
        var Y: Float;
        var Cb: Float;
        var Cr: Float;
        var offset = 0;

        var i = 0;
        var length = data.length;

        while (i < length)
        {
            Y = data.b.fastGet(i);
            Cb = data.b.fastGet(i + 1);
            Cr = data.b.fastGet(i + 2);

            data.set(i, clamp0to255(434.456 - Y - 1.402 * Cr));
            data.set(i + 1, clamp0to255(119.541 - Y + 0.344 * Cb + 0.714 * Cr));
            data.set(i + 2, clamp0to255(481.816 - Y - 1.772 * Cb));
            // K in data[i + 3] is unchanged
            i += 4;
        }
        return data;
    }

    function convertCmykToRgb(data: haxe.io.Bytes): haxe.io.Bytes
    {
        var c: Float;
        var m: Float;
        var y: Float;
        var k: Float;

        var offset = 0;
        var min = -255 * 255 * 255;
        var scale: Float = 1.0 / 255.0 / 255.0;

        var i = 0;
        var length = data.length;

        while (i < length)
        {
            c = data.b.fastGet(i);
            m = data.b.fastGet(i + 1);
            y = data.b.fastGet(i + 2);
            k = data.b.fastGet(i + 3);

            var r =
            c * (-4.387332384609988 * c + 54.48615194189176 * m +
            18.82290502165302 * y + 212.25662451639585 * k -
            72734.4411664936) +
            m * (1.7149763477362134 * m - 5.6096736904047315 * y -
            17.873870861415444 * k - 1401.7366389350734) +
            y * (-2.5217340131683033 * y - 21.248923337353073 * k +
            4465.541406466231) -
            k * (21.86122147463605 * k + 48317.86113160301);
            var g =
            c * (8.841041422036149 * c + 60.118027045597366 * m +
            6.871425592049007 * y + 31.159100130055922 * k -
            20220.756542821975) +
            m * (-15.310361306967817 * m + 17.575251261109482 * y +
            131.35250912493976 * k - 48691.05921601825) +
            y * (4.444339102852739 * y + 9.8632861493405 * k -
            6341.191035517494) -
            k * (20.737325471181034 * k + 47890.15695978492);
            var b =
            c * (0.8842522430003296 * c + 8.078677503112928 * m +
            30.89978309703729 * y - 0.23883238689178934 * k -
            3616.812083916688) +
            m * (10.49593273432072 * m + 63.02378494754052 * y +
            50.606957656360734 * k - 28620.90484698408) +
            y * (0.03296041114873217 * y + 115.60384449646641 * k -
            49363.43385999684) -
            k * (22.33816807309886 * k + 45932.16563550634);

            data.set(offset++, r >= 0 ? 255 : r <= min ? 0 : Std.int(255 + r * scale) | 0);
            data.set(offset++, g >= 0 ? 255 : g <= min ? 0 : Std.int(255 + g * scale) | 0);
            data.set(offset++, b >= 0 ? 255 : b <= min ? 0 : Std.int(255 + b * scale) | 0);

            i += 4;
        }
        return data;
    }

    // From here parsing

    public function parse()
    {
        var offset = 0;
        var length = this.data.length;
        var jfif: Jfif = null;
        var adobe: Adobe = null;
        var pixels = null;
        var frame: Frame = null;
        var resetInterval: Int = 0;
        var quantizationTables: haxe.ds.Vector<haxe.ds.Vector<Int>>;

        quantizationTables = haxe.ds.Vector.fromArrayCopy([
        new haxe.ds.Vector(64),
        new haxe.ds.Vector(64),
        new haxe.ds.Vector(64),
        new haxe.ds.Vector(64)
        ]);

        var huffmanTablesAC:Array<Dynamic> = new Array();
        var huffmanTablesDC:Array<Dynamic> = new Array();

        function readUint16() {
            var value = (data.b.fastGet(offset) << 8) | data.b.fastGet(offset + 1);
            offset += 2;
            return value;
        }

        function readDataBlock(): haxe.io.Bytes {
            var length: Int = readUint16();

            var subLength: Int = length - 2;

            var subArray: haxe.io.Bytes = haxe.io.Bytes.alloc(subLength);
            var subArrayIndex: Int = 0;

            for (i in offset...offset + subLength)
            {
                subArray.set(subArrayIndex, data.get(i));
                ++subArrayIndex;
            }

            offset += subLength;
            return subArray;
        }

        function prepareComponents(frame: Frame) {
            var mcusPerLine = Math.ceil(frame.samplesPerLine / 8 / frame.maxH);
            var mcusPerColumn = Math.ceil(frame.scanLines / 8 / frame.maxV);
            for (i in 0...frame.components.length) {
            var component = frame.components[i];
            var blocksPerLine = Math.ceil(Math.ceil(frame.samplesPerLine / 8) *
            component.h / frame.maxH);
            var blocksPerColumn = Math.ceil(Math.ceil(frame.scanLines  / 8) *
            component.v / frame.maxV);
            var blocksPerLineForMcu = mcusPerLine * component.h;
            var blocksPerColumnForMcu = mcusPerColumn * component.v;

            var blocksBufferSize = 64 * blocksPerColumnForMcu *
            (blocksPerLineForMcu + 1);
            component.blockData = new Vector(blocksBufferSize);
            component.blocksPerLine = blocksPerLine;
            component.blocksPerColumn = blocksPerColumn;
            }
            frame.mcusPerLine = mcusPerLine;
            frame.mcusPerColumn = mcusPerColumn;
        }


        var fileMarker = readUint16();

        if (fileMarker != 0xFFD8) { // SOI (Start of Image)
            throw 'SOI not found';
        }

        fileMarker = readUint16();

        while (fileMarker != 0xFFD9) { // EOI (End of image)
            var i, j, l;
            switch(fileMarker) {
                case 0xFFE0, // APP0 (Application Specific)
                0xFFE1, // APP1
                0xFFE2, // APP2
                0xFFE3, // APP3
                0xFFE4, // APP4
                0xFFE5, // APP5
                0xFFE6, // APP6
                0xFFE7, // APP7
                0xFFE8, // APP8
                0xFFE9, // APP9
                0xFFEA, // APP10
                0xFFEB, // APP11
                0xFFEC, // APP12
                0xFFED, // APP13
                0xFFEE, // APP14
                0xFFEF, // APP15
                0xFFFE: // COM (Comment)

                    var appData = readDataBlock();

                    if (fileMarker == 0xFFE0) {
                        if (appData.b.fastGet(0) == 0x4A && appData.b.fastGet(1) == 0x46 &&
                        appData.b.fastGet(2) == 0x49 && appData.b.fastGet(3) == 0x46 &&
                        appData.b.fastGet(4) == 0) { // 'JFIF\x00'
                            jfif = {
                            version: { major: appData.b.fastGet(5), minor: appData.b.fastGet(6) },
                            densityUnits: appData.b.fastGet(7),
                            xDensity: (appData.b.fastGet(8) << 8) | appData.b.fastGet(9),
                            yDensity: (appData.b.fastGet(10) << 8) | appData.b.fastGet(11),
                            thumbWidth: appData.b.fastGet(12),
                            thumbHeight: appData.b.fastGet(13),
                            thumbData: appData.sub(14, 3 * appData.b.fastGet(12) * appData.b.fastGet(13))
                            };
                        }
                    }
                    // TODO APP1 - Exif
                    if (fileMarker == 0xFFEE) {
                        if (appData.b.fastGet(0) == 0x41 && appData.b.fastGet(1) == 0x64 &&
                        appData.b.fastGet(2) == 0x6F && appData.b.fastGet(3) == 0x62 &&
                        appData.b.fastGet(4) == 0x65) { // 'Adobe'
                            adobe = {
                            version: (appData.b.fastGet(5) << 8) | appData.b.fastGet(6),
                            flags0: (appData.b.fastGet(7) << 8) | appData.b.fastGet(8),
                            flags1: (appData.b.fastGet(9) << 8) | appData.b.fastGet(10),
                            transformCode: appData.b.fastGet(11)
                            };
                        }
                    }

                case 0xFFDB: // DQT (Define Quantization Tables)
                    var quantizationTablesLength = readUint16();
                    var quantizationTablesEnd = quantizationTablesLength + offset - 2;
                    var z;
                    while (offset < quantizationTablesEnd) {
                        var quantizationTableSpec = data.b.fastGet(offset++);
                        var tableData: Vector<Int> = new Vector(64);
                        if ((quantizationTableSpec >> 4) == 0) { // 8 bit values
                            for (j in 0...64) {
                            z = dctZigZag[j];
                            tableData[z] = data.b.fastGet(offset++);
                            }
                        } else if ((quantizationTableSpec >> 4) == 1) { //16 bit
                            for (j in 0...64) {
                            z = dctZigZag[j];
                            tableData[z] = readUint16();
                            }
                        } else {
                            throw 'DQT: invalid table spec';
                        }
                        quantizationTables[quantizationTableSpec & 15] = tableData;
                    }

                case 0xFFC0, // SOF0 (Start of Frame, Baseline DCT)
                0xFFC1, // SOF1 (Start of Frame, Extended DCT)
                0xFFC2: // SOF2 (Start of Frame, Progressive DCT)
                    if (frame != null) {
                        throw 'Only single frame JPEGs supported';
                    }
                    readUint16(); // skip data length
                    frame = {
                        extended: (fileMarker == 0xFFC1),
                        progressive: (fileMarker == 0xFFC2),
                        precision: data.b.fastGet(offset++),
                        scanLines: readUint16(),
                        samplesPerLine: readUint16(),
                        components: new Array<Component>(),
                        componentIds: new Map<Int, Int>()
                    };
                    var componentsCount = data.b.fastGet(offset++), componentId;
                    var maxH = 0, maxV = 0;
                    for (i in 0...componentsCount) {
                componentId = data.b.fastGet(offset);
                var h = data.b.fastGet(offset + 1) >> 4;
                var v = data.b.fastGet(offset + 1) & 15;
                if (maxH < h) {
                maxH = h;
                }
                if (maxV < v) {
                maxV = v;
                }
                var qId = data.b.fastGet(offset + 2);
                l = frame.components.push({
                h: h,
                v: v,
                quantizationTable: quantizationTables[qId]
                });
                frame.componentIds[componentId] = l - 1;
                offset += 3;
                }
                    frame.maxH = maxH;
                    frame.maxV = maxV;
                    prepareComponents(frame);

                case 0xFFC4: // DHT (Define Huffman Tables)
                    var huffmanLength: Int = readUint16();
                    var i: Int = 2;

                    while (i < huffmanLength)
                    {
                        var huffmanTableSpec = data.b.fastGet(offset++);
                        var codeLengths: Vector<Int> = new Vector(16);
                        var codeLengthSum = 0;
                        for (j in 0...16) {
                            codeLengths[j] = data.b.fastGet(offset);
                            codeLengthSum += codeLengths[j];
                            offset++;
                        }
                        var huffmanValues: Vector<Int> = new Vector(codeLengthSum);
                        for (j in 0...codeLengthSum) {
                            huffmanValues[j] = data.b.fastGet(offset);
                            offset++;
                        }

                        i += 17 + codeLengthSum;

                        ((huffmanTableSpec >> 4) == 0 ? huffmanTablesDC : huffmanTablesAC)[huffmanTableSpec & 15] =
                        buildHuffmanTable(codeLengths, huffmanValues);
                    }

                case 0xFFDD: // DRI (Define Restart Interval)
                    readUint16(); // skip data length
                    resetInterval = readUint16();

                case 0xFFDA: // SOS (Start of Scan)
                    var scanLength = readUint16();
                    var selectorsCount = data.b.fastGet(offset++);
                    var components: Array<Component> = new Array();
                    var component: Component;

                    for (i in 0...selectorsCount)
                    {
                        var componentIndex = frame.componentIds[data.b.fastGet(offset++)];
                        component = frame.components[componentIndex];
                        var tableSpec = data.b.fastGet(offset++);
                        component.huffmanTableDC = huffmanTablesDC[tableSpec >> 4];
                        component.huffmanTableAC = huffmanTablesAC[tableSpec & 15];
                        components.push(component);
                    }

                    var spectralStart = data.b.fastGet(offset++);
                    var spectralEnd = data.b.fastGet(offset++);
                    var successiveApproximation = data.b.fastGet(offset++);
                    var processed = decodeScan(data, offset,
                    frame, components, resetInterval,
                    spectralStart, spectralEnd,
                    successiveApproximation >> 4, successiveApproximation & 15);

                    offset += processed;

                case 0xFFFF: // Fill bytes
                    if (data.b.fastGet(offset) != 0xFF) { // Avoid skipping a valid marker.
                        offset--;
                    }

                default:
                    if (data.b.fastGet(offset - 3) == 0xFF && data.b.fastGet(offset - 2) >= 0xC0 && data.b.fastGet(offset - 2) <= 0xFE) {
                        // could be incorrect encoding -- last 0xFF byte of the previous
                        // block was eaten by the encoder
                        offset -= 3;
                    }
                    else
                    {
                        throw 'unknown JPEG marker ' + fileMarker; // TODO display as 16 bit string
                    }

            }
            fileMarker = readUint16();
        }

        this.width = untyped frame.samplesPerLine; // TODO check conversion
        this.height = untyped frame.scanLines; // TODO check conversion
        this.jfif = jfif;
        this.adobe = adobe;
        this.components = new Array();

        for (i in 0...frame.components.length)
        {
            var component: Component = frame.components[i];

            var resultComponent: Component =
            {
                output: buildComponentData(frame, component),
                scaleX: component.h / frame.maxH,
                scaleY: component.v / frame.maxV,
                blocksPerLine: component.blocksPerLine,
                blocksPerColumn: component.blocksPerColumn
            }
            this.components.push(resultComponent);
        }
        this.numComponents = this.components.length;
    }

    function buildHuffmanTable(codeLengths: Vector<Int>, values: Vector<Int>) {
        var k = 0, i, j, length = 16;
        var code: Array<HuffNode> = new Array<HuffNode>();
        while (length > 0 && codeLengths[length - 1] == 0) {
            length--;
        }
        code.push({children: [], index: 0});

        var p: HuffNode = code[0];
        var q: HuffNode;

        for (i in 0...length) {
        for (j in 0...codeLengths[i]) {
        p = code.pop();
        p.children[p.index] = values[k];

        while (p.index > 0) {
        p = code.pop();
        }
        p.index++;
        code.push(p);
        while (code.length <= i)

        {
        code.push(q = {children: [], index: 0});
        p.children[p.index] = q.children;
        p = q;
        }
        k++;
        }
        if (i + 1 < length) {
        // p here points to last
        code.push(q = {children: [], index: 0});
        p.children[p.index] = q.children;
        p = q;
        }
        }
        return code[0].children;
    }

    function getBlockBufferOffset(component: Component, row: Int, col: Int) {
        return 64 * ((component.blocksPerLine + 1) * row + col);
    }

    function decodeScan(data: haxe.io.Bytes, offset, frame: Frame, components: Array<Component>, resetInterval,
                        spectralStart, spectralEnd, successivePrev, successive) {
        var precision = frame.precision;
        var samplesPerLine = frame.samplesPerLine;
        var scanLines = frame.scanLines;
        var mcusPerLine = frame.mcusPerLine;
        var progressive = frame.progressive;
        var maxH = frame.maxH, maxV = frame.maxV;

        var startOffset = offset, bitsData = 0, bitsCount = 0;

        function readBit(): Int
        {
            if (bitsCount > 0) {
                bitsCount--;
                return (bitsData >> bitsCount) & 1;
            }
            bitsData = data.b.fastGet(offset++);
            if (bitsData == 0xFF)
            {
                var nextByte = data.b.fastGet(offset++);
                if (nextByte != 0) {
                    throw 'unexpected marker: ' +
                    ((bitsData << 8) | nextByte); // TODO Convert to 16 bit int string
                }
                // unstuff 0
            }
            bitsCount = 7;
            return bitsData >>> 7;
        }

        function decodeHuffman(tree: Array<Dynamic>): Int
        {
            var node = tree;
            var iteration: Int = 0;
            while (true)
            {
                var index: Int = readBit();

                if (Type.typeof(node[index]) == ValueType.TInt)
                {
                    return node[index];
                }

                if (!Std.is(node[index], Array)) {
                    throw 'invalid huffman sequence';
                }

                node = node[index];
            }
        }

        function receive(length: Int): Int {
            var n = 0;
            while (length > 0) {
                n = (n << 1) | readBit();
                length--;
            }
            return n;
        }

        function receiveAndExtend(length: Int): Int {
            if (length == 1) {
                return readBit() == 1 ? 1 : -1;
            }
            var n = receive(length);
            if (n >= 1 << (length - 1)) {
                return n;
            }
            return n + (-1 << length) + 1;
        }

        function decodeBaseline(component: Component, offset: Int)
        {
            var t = decodeHuffman(component.huffmanTableDC);
            var diff = t == 0 ? 0 : receiveAndExtend(t);
            component.pred += diff;
            component.blockData.set(offset, component.pred);

            var k = 1;

            while (k < 64)
            {
                var rs = decodeHuffman(component.huffmanTableAC);

                var s = rs & 15;
                var r = rs >> 4;

                if (s == 0)
                {
                    if (r < 15)
                    {
                        break;
                    }
                    k += 16;
                    continue;
                }
                k += r;
                var z = dctZigZag[k];
                component.blockData.set(offset + z, receiveAndExtend(s));
                k++;
            }
        }

        function decodeDCFirst(component: Component, offset: Int)
        {
            var t = decodeHuffman(component.huffmanTableDC);
            var diff = t == 0 ? 0 : (receiveAndExtend(t) << successive);
            component.pred += diff;
            component.blockData.set(offset, component.pred);
        }

        function decodeDCSuccessive(component: Component, offset: Int)
        {
            var blockValue: Int = component.blockData.get(offset);
            blockValue |= (readBit() << successive);
            component.blockData.set(offset, blockValue);
        }

        var eobrun = 0;
        function decodeACFirst(component: Component, offset: Int)
        {
            if (eobrun > 0) {
                eobrun--;
                return;
            }
            var k = spectralStart, e = spectralEnd;
            while (k <= e) {
                var rs = decodeHuffman(component.huffmanTableAC);
                var s = rs & 15, r = rs >> 4;
                if (s == 0) {
                    if (r < 15) {
                        eobrun = receive(r) + (1 << r) - 1;
                        break;
                    }
                    k += 16;
                    continue;
                }
                k += r;
                var z = dctZigZag[k];
                component.blockData.set(offset + z, receiveAndExtend(s) * (1 << successive));
                k++;
            }
        }

        var successiveACState = 0;
        var successiveACNextValue = 0;

        function decodeACSuccessive(component: Component, offset: Int)
        {
            var k = spectralStart;
            var e = spectralEnd;
            var r = 0;
            var s;
            var rs;
            while (k <= e) {
                var z = dctZigZag[k];
                switch (successiveACState) {
                    case 0: // initial state
                        rs = decodeHuffman(component.huffmanTableAC);
                        s = rs & 15;
                        r = rs >> 4;
                        if (s == 0) {
                            if (r < 15) {
                                eobrun = receive(r) + (1 << r);
                                successiveACState = 4;
                            } else {
                                r = 16;
                                successiveACState = 1;
                            }
                        } else {
                            if (s != 1) {
                                throw 'invalid ACn encoding';
                            }
                            successiveACNextValue = receiveAndExtend(s);
                            successiveACState = r != 0 ? 2 : 3;
                        }
                        continue;
                    case 1, 2: // skipping r zero items
                        var blockValue: Int = component.blockData.get(offset + z);

                        if (blockValue != 0)
                        {
                            blockValue += (readBit() << successive);
                            component.blockData.set(offset + z, blockValue);
                        } else {
                            r--;
                            if (r == 0) {
                                successiveACState = successiveACState == 2 ? 3 : 0;
                            }
                        }
                    case 3: // set value for a zero item
                        var blockValue: Int = component.blockData.get(offset + z);

                        if (blockValue != 0) {
                            blockValue += (readBit() << successive);
                            component.blockData.set(offset + z, blockValue);
                        } else {
                            component.blockData.set(offset + z, successiveACNextValue << successive);
                            successiveACState = 0;
                        }
                    case 4: // eob
                        var blockValue: Int = component.blockData.get(offset + z);

                        if (blockValue != 0) {
                            blockValue += (readBit() << successive);
                            component.blockData.set(offset + z, blockValue);
                        }
                }
                k++;
            }
            if (successiveACState == 4) {
                eobrun--;
                if (eobrun == 0) {
                    successiveACState = 0;
                }
            }
        }

        function decodeMcu(component: Component, decode, mcu: Int, row: Int, col: Int) {
            var mcuRow: Int = Std.int(mcu / mcusPerLine) | 0;
            var mcuCol: Int = mcu % mcusPerLine;
            var blockRow: Int = mcuRow * component.v + row;
            var blockCol: Int = mcuCol * component.h + col;
            var offset = getBlockBufferOffset(component, blockRow, blockCol);
            decode(component, offset);
        }

        function decodeBlock(component: Component, decode, mcu) {
            var blockRow: Int = Std.int(mcu / component.blocksPerLine) | 0;
            var blockCol: Int = mcu % component.blocksPerLine;
            var offset = getBlockBufferOffset(component, blockRow, blockCol);
            decode(component, offset);
        }

        var componentsLength = components.length;
        var component, i, j, k, n;
        var decodeFn: Component -> Int -> Void;
        if (progressive) {
            if (spectralStart == 0) {
                decodeFn = successivePrev == 0 ? decodeDCFirst : decodeDCSuccessive;
            } else {
                decodeFn = successivePrev == 0 ? decodeACFirst : decodeACSuccessive;
            }
        } else {
            decodeFn = decodeBaseline;
        }

        var mcu = 0, marker;
        var mcuExpected;
        if (componentsLength == 1) {
            mcuExpected = components[0].blocksPerLine * components[0].blocksPerColumn;
        } else {
            mcuExpected = mcusPerLine * frame.mcusPerColumn;
        }
        if (resetInterval == 0) {
            resetInterval = mcuExpected;
        }

        var h: Int;
        var v: Int;
        while (mcu < mcuExpected) {
            // reset interval stuff
            for (i in 0...componentsLength) {
                components[i].pred = 0;
            }
            eobrun = 0;

            if (componentsLength == 1) {
                component = components[0];

                for (n in 0...resetInterval) {
                    decodeBlock(component, decodeFn, mcu);
                    mcu++;
                }
            } else {

                for (n in 0...resetInterval)
                {
                    for (i in 0...componentsLength)
                    {
                        component = components[i];
                        h = component.h;
                        v = component.v;
                        for (j in 0...v)
                        {
                            for (k in 0...h)
                            {
                                decodeMcu(component, decodeFn, mcu, j, k);
                            }
                        }
                    }
                    mcu++;
                }
            }

            // find marker
            bitsCount = 0;
            marker = (data.b.fastGet(offset) << 8) | data.b.fastGet(offset + 1);
            if (marker <= 0xFF00) {
                throw 'marker was not found';
            }

            if (marker >= 0xFFD0 && marker <= 0xFFD7) { // RSTx
                offset += 2;
            } else {
                break;
            }
        }
        return offset - startOffset;
    }

    function buildComponentData(frame: Frame, component: Component): haxe.ds.Vector<Int>
    {
        var blocksPerLine = component.blocksPerLine;
        var blocksPerColumn = component.blocksPerColumn;
        var computationBuffer: Vector<Int> = new Vector(64); // Int16Array

        for (blockRow in 0...blocksPerColumn)
        {
            for (blockCol in 0...blocksPerLine)
            {
                var offset = getBlockBufferOffset(component, blockRow, blockCol);
                quantizeAndInverse(component, offset, computationBuffer);
            }
        }
        return component.blockData;
    }

    // A port of poppler's IDCT method which in turn is taken from:
    //   Christoph Loeffler, Adriaan Ligtenberg, George S. Moschytz,
    //   'Practical Fast 1-D DCT Algorithms with 11 Multiplications',
    //   IEEE Intl. Conf. on Acoustics, Speech & Signal Processing, 1989,
    //   988-991.
    function quantizeAndInverse(component: Component, blockBufferOffset: Int, p: Vector<Int>)
    {
        var qt = component.quantizationTable;
        var blockData = component.blockData;
        var v0, v1, v2, v3, v4, v5, v6, v7;
        var p0, p1, p2, p3, p4, p5, p6, p7;
        var t;

        // inverse DCT on rows
        var row: Int = 0;
        while (row < 64)
        {
            // gather block data
            p0 = blockData.get(blockBufferOffset + row);
            p1 = blockData.get(blockBufferOffset + row + 1);
            p2 = blockData.get(blockBufferOffset + row + 2);
            p3 = blockData.get(blockBufferOffset + row + 3);
            p4 = blockData.get(blockBufferOffset + row + 4);
            p5 = blockData.get(blockBufferOffset + row + 5);
            p6 = blockData.get(blockBufferOffset + row + 6);
            p7 = blockData.get(blockBufferOffset + row + 7);

            // dequant p0
            p0 *= qt[row];

            // check for all-zero AC coefficients
            if ((p1 | p2 | p3 | p4 | p5 | p6 | p7) == 0) {
                t = (dctSqrt2 * p0 + 512) >> 10;
                p[row] = t;
                p[row + 1] = t;
                p[row + 2] = t;
                p[row + 3] = t;
                p[row + 4] = t;
                p[row + 5] = t;
                p[row + 6] = t;
                p[row + 7] = t;
                row += 8;
                continue;
            }

            // dequant p1 ... p7
            p1 *= qt[row + 1];
            p2 *= qt[row + 2];
            p3 *= qt[row + 3];
            p4 *= qt[row + 4];
            p5 *= qt[row + 5];
            p6 *= qt[row + 6];
            p7 *= qt[row + 7];

            // stage 4
            v0 = (dctSqrt2 * p0 + 128) >> 8;
            v1 = (dctSqrt2 * p4 + 128) >> 8;
            v2 = p2;
            v3 = p6;
            v4 = (dctSqrt1d2 * (p1 - p7) + 128) >> 8;
            v7 = (dctSqrt1d2 * (p1 + p7) + 128) >> 8;
            v5 = p3 << 4;
            v6 = p5 << 4;

            // stage 3
            v0 = (v0 + v1 + 1) >> 1;
            v1 = v0 - v1;
            t  = (v2 * dctSin6 + v3 * dctCos6 + 128) >> 8;
            v2 = (v2 * dctCos6 - v3 * dctSin6 + 128) >> 8;
            v3 = t;
            v4 = (v4 + v6 + 1) >> 1;
            v6 = v4 - v6;
            v7 = (v7 + v5 + 1) >> 1;
            v5 = v7 - v5;

            // stage 2
            v0 = (v0 + v3 + 1) >> 1;
            v3 = v0 - v3;
            v1 = (v1 + v2 + 1) >> 1;
            v2 = v1 - v2;
            t  = (v4 * dctSin3 + v7 * dctCos3 + 2048) >> 12;
            v4 = (v4 * dctCos3 - v7 * dctSin3 + 2048) >> 12;
            v7 = t;
            t  = (v5 * dctSin1 + v6 * dctCos1 + 2048) >> 12;
            v5 = (v5 * dctCos1 - v6 * dctSin1 + 2048) >> 12;
            v6 = t;

            // stage 1
            p[row] = v0 + v7;
            p[row + 7] = v0 - v7;
            p[row + 1] = v1 + v6;
            p[row + 6] = v1 - v6;
            p[row + 2] = v2 + v5;
            p[row + 5] = v2 - v5;
            p[row + 3] = v3 + v4;
            p[row + 4] = v3 - v4;
            row += 8;
        }

        // inverse DCT on columns
        var col: Int = 0;
        while (col < 8)
        {
            p0 = p[col];
            p1 = p[col +  8];
            p2 = p[col + 16];
            p3 = p[col + 24];
            p4 = p[col + 32];
            p5 = p[col + 40];
            p6 = p[col + 48];
            p7 = p[col + 56];

            // check for all-zero AC coefficients
            if ((p1 | p2 | p3 | p4 | p5 | p6 | p7) == 0)
            {
                t = (dctSqrt2 * p0 + 8192) >> 14;
                // convert to 8 bit
                t = (t < -2040) ? 0 : (t >= 2024) ? 255 : (t + 2056) >> 4;
                blockData.set(blockBufferOffset + col, t);
                blockData.set(blockBufferOffset + col +  8, t);
                blockData.set(blockBufferOffset + col + 16, t);
                blockData.set(blockBufferOffset + col + 24, t);
                blockData.set(blockBufferOffset + col + 32, t);
                blockData.set(blockBufferOffset + col + 40, t);
                blockData.set(blockBufferOffset + col + 48, t);
                blockData.set(blockBufferOffset + col + 56, t);
                ++col;
                continue;
            }

            // stage 4
            v0 = (dctSqrt2 * p0 + 2048) >> 12;
            v1 = (dctSqrt2 * p4 + 2048) >> 12;
            v2 = p2;
            v3 = p6;
            v4 = (dctSqrt1d2 * (p1 - p7) + 2048) >> 12;
            v7 = (dctSqrt1d2 * (p1 + p7) + 2048) >> 12;
            v5 = p3;
            v6 = p5;

            // stage 3
            // Shift v0 by 128.5 << 5 here, so we don't need to shift p0...p7 when
            // converting to UInt8 range later.
            v0 = ((v0 + v1 + 1) >> 1) + 4112;
            v1 = v0 - v1;
            t  = (v2 * dctSin6 + v3 * dctCos6 + 2048) >> 12;
            v2 = (v2 * dctCos6 - v3 * dctSin6 + 2048) >> 12;
            v3 = t;
            v4 = (v4 + v6 + 1) >> 1;
            v6 = v4 - v6;
            v7 = (v7 + v5 + 1) >> 1;
            v5 = v7 - v5;

            // stage 2
            v0 = (v0 + v3 + 1) >> 1;
            v3 = v0 - v3;
            v1 = (v1 + v2 + 1) >> 1;
            v2 = v1 - v2;
            t  = (v4 * dctSin3 + v7 * dctCos3 + 2048) >> 12;
            v4 = (v4 * dctCos3 - v7 * dctSin3 + 2048) >> 12;
            v7 = t;
            t  = (v5 * dctSin1 + v6 * dctCos1 + 2048) >> 12;
            v5 = (v5 * dctCos1 - v6 * dctSin1 + 2048) >> 12;
            v6 = t;

            // stage 1
            p0 = v0 + v7;
            p7 = v0 - v7;
            p1 = v1 + v6;
            p6 = v1 - v6;
            p2 = v2 + v5;
            p5 = v2 - v5;
            p3 = v3 + v4;
            p4 = v3 - v4;

            // convert to 8-bit integers
            p0 = (p0 < 16) ? 0 : (p0 >= 4080) ? 255 : p0 >> 4;
            p1 = (p1 < 16) ? 0 : (p1 >= 4080) ? 255 : p1 >> 4;
            p2 = (p2 < 16) ? 0 : (p2 >= 4080) ? 255 : p2 >> 4;
            p3 = (p3 < 16) ? 0 : (p3 >= 4080) ? 255 : p3 >> 4;
            p4 = (p4 < 16) ? 0 : (p4 >= 4080) ? 255 : p4 >> 4;
            p5 = (p5 < 16) ? 0 : (p5 >= 4080) ? 255 : p5 >> 4;
            p6 = (p6 < 16) ? 0 : (p6 >= 4080) ? 255 : p6 >> 4;
            p7 = (p7 < 16) ? 0 : (p7 >= 4080) ? 255 : p7 >> 4;

            // store block data
            blockData.set(blockBufferOffset + col, p0);
            blockData.set(blockBufferOffset + col +  8, p1);
            blockData.set(blockBufferOffset + col + 16, p2);
            blockData.set(blockBufferOffset + col + 24, p3);
            blockData.set(blockBufferOffset + col + 32, p4);
            blockData.set(blockBufferOffset + col + 40, p5);
            blockData.set(blockBufferOffset + col + 48, p6);
            blockData.set(blockBufferOffset + col + 56, p7);
            ++col;
        }
    }
}
