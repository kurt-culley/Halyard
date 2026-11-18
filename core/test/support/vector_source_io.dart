import 'dart:io';

/// A vector file's text, read from test/vectors/ (tests run from the package root).
Future<String> readVectorText(String name) => File('test/vectors/$name').readAsString();
