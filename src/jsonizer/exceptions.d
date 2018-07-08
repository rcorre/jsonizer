/**
  * Defines the exceptions that Jsonizer may throw.
  *
  * Authors: <a href="https://github.com/rcorre">rcorre</a>
  * License: <a href="http://opensource.org/licenses/MIT">MIT</a>
  * Copyright: Copyright © 2015, rcorre
  * Date: 3/24/15
  */
module jsonizer.exceptions;

import std.json      : JSONValue, JSON_TYPE;
import std.string    : format, join;
import std.traits    : ParameterTypeTuple, ParameterIdentifierTuple;
import std.meta      : aliasSeqOf;
import std.range     : iota;
import std.typetuple : staticMap;

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
    super(fmt.format(targetType, missingKeys, extraKeys));

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

/// Thrown when a type has no default constructor and the custom constructor cannot be fulfilled.
class JsonizeConstructorException : JsonizeException {
  private enum fmt =
    "%s has no default constructor, and none of the following constructors could be fulfilled: \n" ~
    "%s\n" ~
    "json object:\n %s";

  const {
    TypeInfo targetType; /// Tye type jsonizer was attempting to deserialize to.
    JSONValue json;      /// The json value that was being deserialized
  }

  /// Construct and throw a `JsonizeConstructorException`
  /// Params:
  ///   T = Type being deserialized
  ///   Ctors = constructors that were attempted
  ///   json = json object being deserialized
  static void doThrow(T, Ctors ...)(JSONValue json) {
    static if (Ctors.length > 0) {
      auto signatures = [staticMap!(ctorSignature, Ctors)].join("\n");
    }
    else {
      auto signatures = "<no @jsonized constructors>";
    }

    throw new JsonizeConstructorException(typeid(T), signatures, json);
  }

  private this(TypeInfo targetType, string ctorSignatures, JSONValue json) {
    super(fmt.format(targetType, ctorSignatures, json));

    this.targetType  = targetType;
    this.json = json;
  }
}

private:
// Represent the function signature of a constructor as a string.
template ctorSignature(alias ctor) {
  alias params = ParameterIdentifierTuple!ctor;
  alias types  = ParameterTypeTuple!ctor;

  // build a string "type1 param1, type2 param2, ..., typeN paramN"
  static string paramString() {
    string s = "";

    foreach(i ; aliasSeqOf!(params.length.iota)) {
      s ~= types[i].stringof ~ " " ~ params[i];

      static if (i < params.length - 1) {
        s ~= ", ";
      }
    }

    return s;
  }

  enum ctorSignature = "this(%s)".format(paramString);
}

unittest {
  static class Foo {
    this(string s, int i, float f) { }
  }

  assert(ctorSignature!(Foo.__ctor) == "this(string s, int i, float f)");
}
