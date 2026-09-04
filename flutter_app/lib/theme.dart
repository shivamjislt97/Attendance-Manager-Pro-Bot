import 'package:flutter/material.dart';

const bg = Color(0xFF0B1C30);
const surface = Color(0xFF12263F);
const card = Color(0xFF16294A);
const line = Color(0x2AFFFFFF);
const txt = Color(0xFFEAF1FF);
const mut = Color(0xFF8FA3C0);
const green = Color(0xFF22C55E);
const greenD = Color(0xFF006C49);
const red = Color(0xFFEF4444);
const yellow = Color(0xFFEAB308);
const orange = Color(0xFFF97316);

InputDecoration fld(String hint) =>
    InputDecoration(hintText: hint, hintStyle: const TextStyle(color: mut));

void msg(BuildContext ctx, String t) =>
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(t)));
