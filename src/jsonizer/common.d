module jsonizer.common;

/// use @jsonize to mark members to be (de)serialized from/to json
/// use @jsonize to mark a single contructor to use when creating an object using extract
/// use @jsonize("name") to make a member use the json key "name"
/// use @jsonize(Jsonize.[yes/opt]) to choose whether the parameter is optional
/// use @jsonize(JsonizeIn.[yes/opt/no]) to choose whether the parameter is optional for deserialization
/// use @jsonize(JsonizeOut.[yes/opt/no]) to choose whether the parameter is optional for serialization
struct jsonize {
  /// alternate name used to identify member in json
  string key;

  /// whether member is required during deserialization
  JsonizeIn perform_in = JsonizeIn.unspecified;
  /// whether serialized member
  JsonizeOut perform_out = JsonizeOut.unspecified;

  /// parameters to @jsonize may be specified in any order
  /// valid uses of @jsonize include:
  ///   @jsonize
  ///   @jsonize("foo")
  ///   @jsonize(Jsonize.opt)
  ///   @jsonize("bar", Jsonize.opt)
  ///   @jsonize(Jsonize.opt, "bar")
  this(T ...)(T params) {
    foreach(idx , param ; params) {
      alias type = T[idx];
      static if (is(type == Jsonize)) {
        perform_in = cast(JsonizeIn)param;
        perform_out = cast(JsonizeOut)param;
      }
      else static if (is(type == JsonizeIn)) {
        perform_in = param;
      }
      else static if (is(type == JsonizeOut)) {
        perform_out = param;
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

/// Control the strictness with which a field is deserialized
enum JsonizeIn
{
  /// The default. Equivalent to `yes` unless overridden by another UDA.
  unspecified = 0,
  /// always deserialize this field, fail if it is not present
  yes = 1,
  /// deserialize if found, but continue without error if it is missing
  opt = 2,
  /// never deserialize this field
  no = 3
}

/// Control the strictness with which a field is serialized
enum JsonizeOut
{
  /// the default value -- equivalent to `yes`
  unspecified = 0,
  /// always serialize this field
  yes = 1,
  /// serialize only if it not equal to the initial value of the type
  opt = 2,
  /// never serialize this field
  no = 3
}

/// Shortcut for setting both `JsonizeIn` and `JsonizeOut`
enum Jsonize
{
  /// equivalent to JsonizeIn.yes, JsonizeOut.yes
  yes = 1,
  /// equivalent to  JsonizeIn.opt, JsonizeOut.opt
  opt = 2
}

/// Use of `Jsonize(In,Out)`:
unittest {
  import std.json            : parseJSON;
  import std.exception       : collectException, assertNotThrown;
  import jsonizer.jsonize    : JsonizeMe;
  import jsonizer.fromjson   : fromJSON;
  import jsonizer.exceptions : JsonizeMismatchException;
  static struct S {
    mixin JsonizeMe;

    @jsonize {
      int i; // i is non-opt (default)
      @jsonize(Jsonize.opt) {
        @jsonize("_s") string s; // s is optional
        @jsonize(Jsonize.yes) float f; // f is non-optional (overrides outer attribute)
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

/// Customize the behavior of `toJSON` and `fromJSON`.
struct JsonizeOptions {
  /**
   * A default-constructed `JsonizeOptions`.
   * Used implicilty if no explicit options are given to `fromJSON` or `toJSON`.
   */
  static immutable defaults = JsonizeOptions.init;

  /**
   * The key of a field identifying the D type of a json object.
   *
   * If this key is found in the json object, `fromJSON` will try to factory
   * construct an object of the type identified.
   *
   * This is useful when deserializing a collection of some type `T`, where the
   * actual instances may be different subtypes of `T`.
   *
   * Setting `classKey` to null will disable factory construction.
   */
  string classKey = "class";

  /**
   * A function to attempt identifier remapping from the name found under `classKey`.
   *
   * If this function is provided, then when the `classKey` is found, this function
   * will attempt to remap the value.  This function should return either the fully
   * qualified class name or null.  Returned non-null values indicate that the
   * remapping has succeeded.  A null value will indicate the mapping has failed
   * and the original value will be used in the object factory.
   *
   * This is particularly useful when input JSON has not originated from D.
   */
  string delegate(string) classMap;
}

package:
// Get the json key corresponding to  `T.member`.
template jsonKey(T, string member) {
    alias attrs = T._getUDAs!(member, jsonize);
    static if (!attrs.length)
      enum jsonKey = member;
    else static if (attrs[$ - 1].key)
      enum jsonKey = attrs[$ - 1].key;
    else
      enum jsonKey = member;
}
