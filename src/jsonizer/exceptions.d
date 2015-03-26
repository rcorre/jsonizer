/**
  * Defines the exceptions that Jsonizer may throw.
  *
  * Authors: <a href="https://github.com/rcorre">rcorre</a>
	* License: <a href="http://opensource.org/licenses/MIT">MIT</a>
	* Copyright: Copyright © 2015, rcorre
  * Date: 3/24/15
  */
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
  private enum fmt =
    "fromJSON!%s expected json type to be one of %s but got json type %s. json input: %s";

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

/// Thrown when the keys of a json object fail to match up with the members of the target type.
class JsonizeMismatchException : JsonizeException {
  private enum fmt =
    "Failed to deserialize %s.\n" ~
    "Missing non-optional members: %s.\n" ~
    "Extra keys in json: %s.\n";

  const {
    TypeInfo targetType;  /// Type jsonizer was attempting to deserialize to.
    string[] extraKeys;   /// keys present in json that do not match up to a member.
    string[] missingKeys; /// non-optional members that were not found in the json.
  }

  this(TypeInfo targetType, string[] extraKeys, string[] missingKeys) {
    super(fmt.format(targetType, extraKeys, missingKeys));

    this.targetType  = targetType;
    this.extraKeys   = extraKeys;
    this.missingKeys = missingKeys;
  }
}

unittest {
  import std.algorithm : all, canFind;
  import std.conv : to;

  static class MyClass { }

  auto targetType  = typeid(MyClass);
  auto extraKeys   = [ "who", "what" ];
  auto missingKeys = [ "where" ];

  auto e = new JsonizeMismatchException(targetType, extraKeys, missingKeys);
  assert(e.targetType == targetType);
  assert(e.extraKeys == extraKeys);
  assert(e.missingKeys == missingKeys);
  assert(e.msg.canFind(targetType.to!string),
      "JsonizeMismatchException should report type argument");
  assert(extraKeys.all!(x => e.msg.canFind(x)),
      "JsonizeTypeException should report all extra keys");
  assert(missingKeys.all!(x => e.msg.canFind(x)),
      "JsonizeTypeException should report all missing keys");
}
