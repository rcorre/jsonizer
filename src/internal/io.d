/// helpers for working with files containing JSON data
module internal.io;

import std.json;
import std.file;
import internal.tojson;
import internal.extract;

// Reading/Writing JSON Files
/// read a json-constructable object from a file
T readJSON(T)(string file) {
  auto json = parseJSON(readText(file));
  return extract!T(json);
}

/// shortcut to read file directly into JSONValue
auto readJSON(string file) {
  return parseJSON(readText(file));
}

/// write a jsonizeable object to a file
void writeJSON(T)(T obj, string file) {
  auto json = toJSON!T(obj);
  file.write(json.toPrettyString);
}
