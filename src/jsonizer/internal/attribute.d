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

// TODO: use std.typecons : Flag instead? Would likely need to public import.
/// Whether to silently ignore json keys that do not map to serialized members.
enum JsonizeIgnoreExtraKeys {
  no, /// silently ignore extra keys in the json object being deserialized
  yes /// fail if the json object contains a keys that does not map to a serialized field
}
