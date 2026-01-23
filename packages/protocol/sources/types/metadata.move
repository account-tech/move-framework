/// This module manages the metadata field of Account.
/// It provides the interface to create and get the fields of a Metadata struct.

module account_protocol::metadata;

// === Imports ===

use std::string::String;
use sui::vec_map::{Self, VecMap};

// === Errors ===

const EMetadataNotSameLength: u64 = 0;

// === Structs ===

/// Parent struct protecting the metadata
public struct Metadata has copy, drop, store {
    inner: VecMap<String, String>
}

// === Public functions ===

/// Creates an empty Metadata struct
public fun empty(): Metadata {
    Metadata { inner: vec_map::empty() }
}

/// Creates a new Metadata struct from keys and values.
public fun from_keys_values(keys: vector<String>, values: vector<String>): Metadata {
    assert!(keys.length() == values.length(), EMetadataNotSameLength);
    Metadata {
        inner: vec_map::from_keys_values(keys, values)
    }
}

/// Gets the value for the key.
public fun get(metadata: &Metadata, key: String): String {
    *metadata.inner.get(&key)
}

/// Gets the entry at the index.
public fun get_entry_by_idx(metadata: &Metadata, idx: u64): (String, String) {
    let (key, value) = metadata.inner.get_entry_by_idx(idx);
    (*key, *value)
}

/// Returns the number of entries.
public fun length(metadata: &Metadata): u64 {
    metadata.inner.length()
}

//**************************************************************************************************//
// Tests                                                                                            //
//**************************************************************************************************//

// === Test Helpers ===

#[test_only]
use std::unit_test::{assert_eq, destroy};

// === Unit Tests ===

#[test]
fun test_empty() {
    let metadata = empty();
    assert_eq!(length(&metadata), 0);
    destroy(metadata);
}

#[test]
fun test_from_keys_values() {
    let keys = vector[b"key1".to_string(), b"key2".to_string()];
    let values = vector[b"value1".to_string(), b"value2".to_string()];
    
    let metadata = from_keys_values(keys, values);
    assert_eq!(length(&metadata), 2);
    assert_eq!(get(&metadata, b"key1".to_string()), b"value1".to_string());
    assert_eq!(get(&metadata, b"key2".to_string()), b"value2".to_string());
    
    destroy(metadata);
}

#[test, expected_failure(abort_code = EMetadataNotSameLength)]
fun test_from_keys_values_different_lengths() {
    let keys = vector[b"key1".to_string(), b"key2".to_string()];
    let values = vector[b"value1".to_string()];
    
    let metadata = from_keys_values(keys, values);
    destroy(metadata);
}

#[test]
fun test_get() {
    let keys = vector[b"test_key".to_string()];
    let values = vector[b"test_value".to_string()];
    
    let metadata = from_keys_values(keys, values);
    let value = get(&metadata, b"test_key".to_string());
    assert_eq!(value, b"test_value".to_string());
    
    destroy(metadata);
}

#[test]
fun test_get_entry_by_idx() {
    let keys = vector[b"key1".to_string(), b"key2".to_string()];
    let values = vector[b"value1".to_string(), b"value2".to_string()];
    
    let metadata = from_keys_values(keys, values);
    
    let (key1, value1) = get_entry_by_idx(&metadata, 0);
    let (key2, value2) = get_entry_by_idx(&metadata, 1);
    
    assert_eq!(key1, b"key1".to_string());
    assert_eq!(value1, b"value1".to_string());
    assert_eq!(key2, b"key2".to_string());
    assert_eq!(value2, b"value2".to_string());
    
    destroy(metadata);
}

#[test]
fun test_size() {
    let metadata = empty();
    assert_eq!(length(&metadata), 0);
    
    let keys = vector[b"key1".to_string()];
    let values = vector[b"value1".to_string()];
    let metadata2 = from_keys_values(keys, values);
    assert_eq!(length(&metadata2), 1);
    
    destroy(metadata);
    destroy(metadata2);
}

#[test]
fun test_multiple_entries() {
    let keys = vector[b"name".to_string(), b"description".to_string(), b"version".to_string()];
    let values = vector[b"Test Account".to_string(), b"A test account".to_string(), b"1.0".to_string()];
    
    let metadata = from_keys_values(keys, values);
    assert_eq!(length(&metadata), 3);
    assert_eq!(get(&metadata, b"name".to_string()), b"Test Account".to_string());
    assert_eq!(get(&metadata, b"description".to_string()), b"A test account".to_string());
    assert_eq!(get(&metadata, b"version".to_string()), b"1.0".to_string());
    
    destroy(metadata);
}