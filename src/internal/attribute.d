/// the `jsonize` struct is used as an attribute to mark serialized members
module internal.attribute;

/// whether to fail deserialization if field is not found in json
enum JsonizeOptional {
  no, /// field is required -- fail deserialization if not found in json
  yes /// field is optional -- deserialization can continue if field is not found in json
}

/// use @jsonize to mark members to be (de)serialized from/to json
/// use @jsonize to mark a single contructor to use when creating an object using extract
/// use @jsonize("name") to make a member use the json key "name"
struct jsonize {
  string key;
  JsonizeOptional optional;
}
