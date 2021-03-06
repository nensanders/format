﻿/*
 * format - haXe File Formats
 *
 *  JPG File Format
 *  Copyright (C) 2007-2009 Trevor McCauley, Baluta Cristian (hx port) & Robert Sköld (format conversion)
 *
 * Copyright (c) 2009, The haXe Project Contributors
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

typedef Data = {
	var width : Int;
	var height : Int;
	var quality : Float;
	var pixels : haxe.io.Bytes;
}

typedef Jfif = {
    var version : JfifVersion;
    var densityUnits : Int;
    var xDensity : Int;
    var yDensity : Int;
    var thumbWidth : Int;
    var thumbHeight : Int;
    var thumbData : haxe.io.Bytes;
}

typedef JfifVersion = {
    var major : Int;
    var minor : Int;
}

typedef Adobe = {
    var version: Int;
    var flags0: Int;
    var flags1: Int;
    var transformCode: Int;
}

typedef Frame = {
    @:optional var extended: Bool;
    @:optional var progressive: Bool;
    @:optional var precision: Int;
    @:optional var scanLines: Int;
    @:optional var samplesPerLine: Int;
    @:optional var maxH: Int;
    @:optional var maxV: Int;
    @:optional var mcusPerLine: Int;
    @:optional var mcusPerColumn: Int;
    @:optional var components: Array<Component>;
    @:optional var componentIds: Map<Int, Int>;
}

typedef Component = {
    @:optional var h: Int;
    @:optional var v: Int;
    @:optional var pred: Int;
    @:optional var blocksPerLine: Int;
    @:optional var blocksPerColumn: Int;
    @:optional var blockData: haxe.ds.Vector<Int>;
    @:optional var quantizationTable: haxe.ds.Vector<UInt>;
    @:optional var huffmanTableDC: Array<HuffValue>;
    @:optional var huffmanTableAC: Array<HuffValue>;
    @:optional var scaleX: Float;
    @:optional var scaleY: Float;
    @:optional var output: haxe.ds.Vector<Int>;
}

typedef HuffNode = {
    var children: Array<HuffValue>;
    var index: Int;
}

typedef HuffValue = {
    var value: UInt;
    var isLeaf: Bool;
    var children: Array<HuffValue>;
}
