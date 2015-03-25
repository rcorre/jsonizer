module jsonizer.exceptions;

import std.json : JSONValue, JSON_TYPE;
import std.string : format;

/// Base class of any exception thrown by `jsonizer`.
class JsonizeException : Exception {
  this(string msg) {
    super(msg);
  }
}

/// Thrown when `fromJSON` cannot convert a `JSONValue` into the requested type.
class JsonizeTypeException : Exception {
  enum fmt = "fromJSON!%s expected json type to be one of %s but got json type %s. json input: %s";

  const {
    TypeInfo targetType;  /// Type jsonizer was attempting to deserialize to.
    JSONValue json;       /// The json value that was being deserialized
    JSON_TYPE[] expected; /// The JSON_TYPEs that would have been acceptable
  }

  this(TypeInfo targetType, JSONValue json, JSON_TYPE[] expected ...) {
    super(fmt.format(targetType, expected, json.type, json));

    this.targetType = targetType;
    this.json       = json;
    this.expected   = expected;
  }
}

unittest {
  import std.algorithm : canFind;

  auto json       = JSONValue(4.2f);
  auto targetType = typeid(bool);
  auto expected   = [JSON_TYPE.TRUE, JSON_TYPE.FALSE];

  auto e = new JsonizeTypeException(targetType, json, JSON_TYPE.TRUE, JSON_TYPE.FALSE);

  assert(e.json == json);
  assert(e.targetType == targetType);
  assert(e.expected == expected);
  assert(e.msg.canFind("fromJSON!bool"),
      "JsonizeTypeException should report type argument");
  assert(e.msg.canFind("TRUE") && e.msg.canFind("FALSE"),
      "JsonizeTypeException should report all acceptable json types");
}
