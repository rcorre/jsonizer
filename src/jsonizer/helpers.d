/// helpers for working with files containing JSON data
module jsonizer.helpers;

import std.json;
import std.file;
import jsonizer.tojson;
import jsonizer.fromjson;

/// Read a json-constructable object from a file.
/// Params:
///   path = filesystem path to json file
/// Returns: object parsed from json file
T readJSON(T)(string path) {
  auto json = parseJSON(readText(path));
  return fromJSON!T(json);
}

/// Read contents of a json file directly into a JSONValue.
/// Params:
///   path = filesystem path to json file
/// Returns: a `JSONValue` parsed from the file
auto readJSON(string path) {
  return parseJSON(readText(path));
}

/// Write a jsonizeable object to a file.
/// Params:
///   path = filesystem path to write json to
///   obj  = object to convert to json and write to path
void writeJSON(T)(string path, T obj) {
  auto json = toJSON!T(obj);
  path.write(json.toPrettyString);
}
