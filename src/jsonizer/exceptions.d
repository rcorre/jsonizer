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
import std.typecons  : staticIota;
import std.typetuple : staticMap;

/// Base class of any exception thrown by `jsonizer`.
class JsonizeException : Exception {
  private enum fmt = "Failed to convert JSON_TYPE.%s to %s";

  const {
    TypeInfo targetType; /// The type jsonizer was attempting to deserialize to.
    JSONValue json;      /// The json object that was being deserialized.
  }

  this(TypeInfo targetType, JSONValue json, string extraMessage = null) {
    this.json = json;
    this.targetType = targetType;
    if (extraMessage is null) {
      super(fmt.format(json.type, targetType));
    }
    else {
      super(fmt.format(json.type, targetType) ~ "\n" ~ extraMessage);
    }
  }
}

unittest {
  import std.algorithm : canFind;

  auto json       = JSONValue(4.2f);
  auto targetType = typeid(bool);

  auto e = new JsonizeException(targetType, json);

  assert(e.json == json);
  assert(e.targetType == targetType);
  assert(e.msg.canFind("bool"), "JsonizeTypeException should report target type");
  assert(e.msg.canFind("FLOAT"), "JsonizeTypeException should report encountered json type");
}

/// Thrown when the keys of a json object fail to match up with the members of the target type.
class JsonizeMismatchException : JsonizeException {
  private enum fmt =
    "Missing non-optional members: %s.\n" ~
    "Extra keys in json: %s.\n";

  const {
    string[] extraKeys;   /// keys present in json that do not match up to a member.
    string[] missingKeys; /// non-optional members that were not found in the json.
  }

  this(TypeInfo targetType, JSONValue json, string[] extraKeys, string[] missingKeys) {
    this.extraKeys   = extraKeys;
    this.missingKeys = missingKeys;
    string extraMsg = fmt.format(missingKeys, extraKeys);
    super(targetType, json, extraMsg);
  }
}

unittest {
  import std.algorithm : all, canFind;
  import std.conv : to;

  static class MyClass { }

  JSONValue json = ["a": 5];
  auto targetType  = typeid(MyClass);
  auto extraKeys   = [ "who", "what" ];
  auto missingKeys = [ "where" ];

  auto e = new JsonizeMismatchException(targetType, json, extraKeys, missingKeys);
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
    "%s\n";

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
    string extraMsg = fmt.format(targetType, ctorSignatures);
    super(targetType, json, fmt.format(targetType, json, extraMsg));
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

    foreach(i ; staticIota!(0, params.length)) {
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
