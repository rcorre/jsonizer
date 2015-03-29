module jsonizer.internal.attribute;

/// use @jsonize to mark members to be (de)serialized from/to json
/// use @jsonize to mark a single contructor to use when creating an object using extract
/// use @jsonize("name") to make a member use the json key "name"
/// use @jsonize(JsonizeOptional.[yes/no]) to choose whether the parameter is optional
struct jsonize {
  /// alternate name used to identify member in json
  string key;
  /// whether member is required during deserialization
  JsonizeOptional optional = JsonizeOptional.unspecified;

  /// parameters to @jsonize may be specified in any order
  /// valid uses of @jsonize include:
  ///   @jsonize
  ///   @jsonize("foo")
  ///   @jsonize(JsonizeOptional.yes)
  ///   @jsonize("bar", JsonizeOptional.yes)
  ///   @jsonize(JsonizeOptional.yes, "bar")
  this(T ...)(T params) {
    foreach(idx , param ; params) {
      alias type = T[idx];
      static if (is(type == JsonizeOptional)) {
        optional = param;
      }
      else static if (is(type : string)) {
        key = param;
      }
      else {
        assert(0, "invalid @jsonize parameter of type " ~ typeid(type));
      }
    }
  }
}

/// whether to fail deserialization if field is not found in json
enum JsonizeOptional {
  unspecified, /// optional status not specified (currently defaults to `no`)
  no,          /// field is required -- fail deserialization if not found in json
  yes          /// field is optional -- deserialization can continue if field is not found in json
}

/// Use of `JsonizeOptional`:
unittest {
  import std.json            : parseJSON;
  import std.exception       : collectException, assertNotThrown;
  import jsonizer.jsonize    : JsonizeMe;
  import jsonizer.fromjson   : fromJSON;
  import jsonizer.exceptions : JsonizeMismatchException;
  static struct S {
    mixin JsonizeMe;

    @jsonize {
      int i; // i is non-optional (default)
      @jsonize(JsonizeOptional.yes) {
        @jsonize("_s") string s; // s is optional
        @jsonize(JsonizeOptional.no) float f; // f is non-optional (overrides outer attribute)
      }
    }
  }

  assertNotThrown(`{ "i": 5, "f": 0.2}`.parseJSON.fromJSON!S);
  auto ex = collectException!JsonizeMismatchException(`{ "i": 5 }`.parseJSON.fromJSON!S);

  assert(ex !is null, "missing non-optional field 'f' should trigger JsonizeMismatchException");
  assert(ex.targetType == typeid(S));
  assert(ex.missingKeys == [ "f" ]);
  assert(ex.extraKeys == [ ]);
}

// TODO: use std.typecons : Flag instead? Would likely need to public import.
/// Whether to silently ignore json keys that do not map to serialized members.
enum JsonizeIgnoreExtraKeys {
  no, /// silently ignore extra keys in the json object being deserialized
  yes /// fail if the json object contains a keys that does not map to a serialized field
}


/// Use of `JsonizeIgnoreExtraKeys`:
unittest {
  import std.json            : parseJSON;
  import std.exception       : collectException, assertNotThrown;
  import jsonizer.jsonize    : JsonizeMe;
  import jsonizer.fromjson   : fromJSON;
  import jsonizer.exceptions : JsonizeMismatchException;

  static struct NoCares {
    mixin JsonizeMe;
    @jsonize {
      int i;
      float f;
    }
  }

  static struct VeryStrict {
    mixin JsonizeMe!(JsonizeIgnoreExtraKeys.no);
    @jsonize {
      int i;
      float f;
    }
  }

  // no extra fields, neither should throw
  assertNotThrown(`{ "i": 5, "f": 0.2}`.parseJSON.fromJSON!NoCares);
  assertNotThrown(`{ "i": 5, "f": 0.2}`.parseJSON.fromJSON!VeryStrict);

  // extra field "s"
  // `NoCares` ignores extra keys, so it will not throw
  assertNotThrown(`{ "i": 5, "f": 0.2, "s": "hi"}`.parseJSON.fromJSON!NoCares);
  // `VeryStrict` does not ignore extra keys
  auto ex = collectException!JsonizeMismatchException(
      `{ "i": 5, "f": 0.2, "s": "hi"}`.parseJSON.fromJSON!VeryStrict);

  assert(ex !is null, "extra field 's' should trigger JsonizeMismatchException");
  assert(ex.targetType == typeid(VeryStrict));
  assert(ex.missingKeys == [ ]);
  assert(ex.extraKeys == [ "s" ]);
}
