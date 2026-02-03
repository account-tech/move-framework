/// Dependencies are the packages that an Account object can call.
/// They are stored in a vector and can be modified through an intent.
/// account_protocol is the only mandatory dependency, found at index 0.
/// 
/// For improved security, we provide a whitelist of allowed packages in Extensions.
/// If unverified_allowed is false, then only these packages can be added.

module account_protocol::deps;

// === Imports ===

use std::string::String;
use account_extensions::extensions::Extensions;
use account_protocol::version_witness::VersionWitness;

// === Errors ===

const EDepNotFound: u64 = 0;
const EDepAlreadyExists: u64 = 1;
const ENotDep: u64 = 2;
const ENotExtension: u64 = 3;
const EAccountProtocolMissing: u64 = 4;
const EDepsNotSameLength: u64 = 5;
const EAccountConfigMissing: u64 = 6;

// === Structs ===

/// Parent struct protecting the deps
public struct Deps has copy, drop, store {
    inner: vector<Dep>,
    // can community extensions be added
    unverified_allowed: bool,
}

/// Child struct storing the name, package and version of a dependency
public struct Dep has copy, drop, store {
    // name of the package
    name: String,
    // id of the package
    addr: address,
    // version of the package
    version: u64,
}

// === Public functions ===

/// Creates a new Deps struct, account_protocol must be the first dependency.
public fun new(
    extensions: &Extensions,
    unverified_allowed: bool,
    names: vector<String>,
    addresses: vector<address>,
    mut versions: vector<u64>,
): Deps {
    assert!(names.length() == addresses.length() && addresses.length() == versions.length(), EDepsNotSameLength);
    assert!(
        names[0] == "account_protocol" &&
        extensions.is_extension(names[0], addresses[0], versions[0]), 
        EAccountProtocolMissing
    );
    // second dependency must be AccountConfig (we don't know the name)
    assert!(names[1] != "account_actions", EAccountConfigMissing);

    let mut inner = vector<Dep>[];

    names.zip_do!(addresses, |name, addr| {
        let version = versions.remove(0);
        
        assert!(!inner.any!(|dep| dep.name == name), EDepAlreadyExists);
        assert!(!inner.any!(|dep| dep.addr == addr), EDepAlreadyExists);
        if (!unverified_allowed) 
            assert!(extensions.is_extension(name, addr, version), ENotExtension);

        inner.push_back(Dep { name, addr, version });
    });

    Deps { inner, unverified_allowed }
}

/// Creates a new Deps struct from latest packages for names.
/// Unverified packages are not allowed after this operation.
public fun new_latest_extensions(
    extensions: &Extensions,
    names: vector<String>,
): Deps {
    assert!(names[0] == "account_protocol", EAccountProtocolMissing);

    let mut inner = vector<Dep>[];

    names.do!(|name| {
        assert!(!inner.any!(|dep| dep.name == name), EDepAlreadyExists);
        let (addr, version) = extensions.get_latest_for_name(name);
        
        inner.push_back(Dep { name, addr, version });
    });

    Deps { inner, unverified_allowed: false }
}

public fun new_inner(
    extensions: &Extensions,
    deps: &Deps,
    names: vector<String>,
    addresses: vector<address>,
    mut versions: vector<u64>,
): vector<Dep> {
    assert!(names.length() == addresses.length() && addresses.length() == versions.length(), EDepsNotSameLength);
    // account_protocol is mandatory and cannot be removed
    assert!(
        names[0] == "account_protocol" &&
        extensions.is_extension(names[0], addresses[0], versions[0]), 
        EAccountProtocolMissing
    );
    // AccountConfig is mandatory and cannot be removed
    assert!(names[1] == deps.get_by_idx(1).name, EAccountConfigMissing);

    let mut inner = vector<Dep>[];
    names.zip_do!(addresses, |name, addr| {
        let version = versions.remove(0);
        
        assert!(!inner.any!(|dep| dep.name == name), EDepAlreadyExists);
        assert!(!inner.any!(|dep| dep.addr == addr), EDepAlreadyExists);
        if (!deps.unverified_allowed) 
            assert!(extensions.is_extension(name, addr, version), ENotExtension);

        inner.push_back(Dep { name, addr, version });
    });

    inner
}

/// Safe because deps_mut is only accessible in this package.
public fun inner_mut(deps: &mut Deps): &mut vector<Dep> {
    &mut deps.inner
}

// === View functions ===

/// Checks if a package is a dependency.
public fun check(deps: &Deps, version_witness: VersionWitness) {
    assert!(deps.contains_addr(version_witness.package_addr()), ENotDep);
}

/// Returns true if unverified packages are allowed.
public fun unverified_allowed(deps: &Deps): bool {
    deps.unverified_allowed
}

/// Returns a dependency by index.
public fun get_by_idx(deps: &Deps, idx: u64): &Dep {
    &deps.inner[idx]
}

/// Returns a dependency by name.
public fun get_by_name(deps: &Deps, name: String): &Dep {
    let opt = deps.inner.find_index!(|dep| dep.name == name);
    assert!(opt.is_some(), EDepNotFound);
    let idx = opt.destroy_some();

    &deps.inner[idx]
}

/// Returns a dependency by address.
public fun get_by_addr(deps: &Deps, addr: address): &Dep {
    let opt = deps.inner.find_index!(|dep| dep.addr == addr);
    assert!(opt.is_some(), EDepNotFound);
    let idx = opt.destroy_some();
    
    &deps.inner[idx]
}

/// Returns the number of dependencies.
public fun length(deps: &Deps): u64 {
    deps.inner.length()
}

/// Returns the name of a dependency.
public fun name(dep: &Dep): String {
    dep.name
}

/// Returns the address of a dependency.
public fun addr(dep: &Dep): address {
    dep.addr
}

/// Returns the version of a dependency.
public fun version(dep: &Dep): u64 {
    dep.version
}

/// Returns true if a dependency exists by name.
public fun contains_name(deps: &Deps, name: String): bool {
    deps.inner.any!(|dep| dep.name == name)
}

/// Returns true if a dependency exists by address.
public fun contains_addr(deps: &Deps, addr: address): bool {
    deps.inner.any!(|dep| dep.addr == addr)
}

// === Package functions ===

/// Toggles the unverified_allowed flag.
public(package) fun toggle_unverified_allowed(deps: &mut Deps) {
    deps.unverified_allowed = !deps.unverified_allowed;
}

//**************************************************************************************************//
// Test functions                                                                                   //
//**************************************************************************************************//

// === Test Helpers ===

#[test_only]
public fun new_for_testing(): Deps {
    Deps {
        inner: vector[
            Dep { name: "account_protocol", addr: @account_protocol, version: 1 },
            Dep { name: "account_config", addr: @0x1, version: 1 },
            Dep { name: "account_actions", addr: @0x2, version: 1 }
        ],
        unverified_allowed: false
    }
}

#[test_only]
public fun toggle_unverified_allowed_for_testing(deps: &mut Deps) {
    deps.unverified_allowed = !deps.unverified_allowed;
}

// === Unit Tests ===

#[test_only]
use std::unit_test::{assert_eq, destroy};
#[test_only]
use account_protocol::version_witness;

#[test]
fun test_inner_mut() {
    let mut deps = Deps {
        inner: vector[
            Dep { name: "account_protocol", addr: @account_protocol, version: 1 },
            Dep { name: "account_config", addr: @0x1, version: 1 },
            Dep { name: "account_actions", addr: @0x2, version: 1 }
        ],
        unverified_allowed: false
    };
    let inner = inner_mut(&mut deps);
    
    assert_eq!(inner.length(), 3);
    inner.push_back(Dep { name: "new_dep", addr: @0x3, version: 1 });
    assert_eq!(inner.length(), 4);
    
    destroy(deps);
}

#[test]
fun test_check_success() {
    let deps = Deps {
        inner: vector[
            Dep { name: "account_protocol", addr: @account_protocol, version: 1 },
            Dep { name: "account_config", addr: @0x1, version: 1 },
            Dep { name: "account_actions", addr: @0x2, version: 1 }
        ],
        unverified_allowed: false
    };
    let witness = version_witness::new_for_testing(@account_protocol);
    
    check(&deps, witness);
}

#[test, expected_failure(abort_code = ENotDep)]
fun test_check_failure() {
    let deps = Deps {
        inner: vector[
            Dep { name: "account_protocol", addr: @account_protocol, version: 1 },
            Dep { name: "account_config", addr: @0x1, version: 1 },
            Dep { name: "account_actions", addr: @0x2, version: 1 }
        ],
        unverified_allowed: false
    };
    let witness = version_witness::new_for_testing(@0xDEAD);
    
    check(&deps, witness);
}

#[test]
fun test_get_by_idx() {
    let deps = new_for_testing();
    let dep = get_by_idx(&deps, 0);
    
    assert_eq!(dep.name, "account_protocol");
    assert_eq!(dep.addr, @account_protocol);
    assert_eq!(dep.version, 1);
}

#[test]
fun test_get_by_name_success() {
    let deps = new_for_testing();
    let dep = get_by_name(&deps, "account_protocol");
    
    assert_eq!(dep.name, "account_protocol");
    assert_eq!(dep.addr, @account_protocol);
    assert_eq!(dep.version, 1);
}

#[test, expected_failure(abort_code = EDepNotFound)]
fun test_get_by_name_not_found() {
    let deps = new_for_testing();
    let _dep = get_by_name(&deps, "non_existent");
}

#[test, expected_failure(abort_code = EDepNotFound)]
fun test_get_by_name_empty_string() {
    let deps = new_for_testing();
    let _dep = get_by_name(&deps, "");
}

#[test]
fun test_get_by_addr_success() {
    let deps = new_for_testing();
    let dep = get_by_addr(&deps, @account_protocol);
    
    assert_eq!(dep.name, "account_protocol");
    assert_eq!(dep.addr, @account_protocol);
    assert_eq!(dep.version, 1);
}

#[test, expected_failure(abort_code = EDepNotFound)]
fun test_get_by_addr_not_found() {
    let deps = new_for_testing();
    let _dep = get_by_addr(&deps, @0xDEAD);
}

#[test, expected_failure(abort_code = EDepNotFound)]
fun test_get_by_addr_zero_address() {
    let deps = new_for_testing();
    let _dep = get_by_addr(&deps, @0x0);
}

#[test]
fun test_length() {
    let deps = new_for_testing();
    assert_eq!(length(&deps), 3);
}

#[test]
fun test_name_addr_version() {
    let deps = new_for_testing();
    let dep = get_by_idx(&deps, 0);
    
    assert_eq!(name(dep), "account_protocol");
    assert_eq!(addr(dep), @account_protocol);
    assert_eq!(version(dep), 1);
}

#[test]
fun test_contains_name_true() {
    let deps = new_for_testing();
    assert!(contains_name(&deps, "account_protocol"));
    assert!(contains_name(&deps, "account_config"));
    assert!(contains_name(&deps, "account_actions"));
}

#[test]
fun test_contains_name_false() {
    let deps = new_for_testing();
    assert!(!contains_name(&deps, "non_existent"));
    assert!(!contains_name(&deps, ""));
}

#[test]
fun test_contains_name_empty_deps() {
    let deps = Deps { inner: vector[], unverified_allowed: false };
    assert!(!contains_name(&deps, "any_name"));
}

#[test]
fun test_contains_addr_true() {
    let deps = new_for_testing();
    assert!(contains_addr(&deps, @account_protocol));
    assert!(contains_addr(&deps, @0x1));
    assert!(contains_addr(&deps, @0x2));
}

#[test]
fun test_contains_addr_false() {
    let deps = new_for_testing();
    assert!(!contains_addr(&deps, @0xDEAD));
    assert!(!contains_addr(&deps, @0x0));
    assert!(!contains_addr(&deps, @0x3));
}

#[test]
fun test_contains_addr_empty_deps() {
    let deps = Deps { inner: vector[], unverified_allowed: false };
    assert!(!contains_addr(&deps, @0x1));
}

#[test]
fun test_toggle_unverified_allowed() {
    let mut deps = new_for_testing();
    
    // Start with false
    assert!(!unverified_allowed(&deps));
    
    // Toggle to true
    toggle_unverified_allowed(&mut deps);
    assert!(unverified_allowed(&deps));
    
    // Toggle back to false
    toggle_unverified_allowed(&mut deps);
    assert!(!unverified_allowed(&deps));
    
    // Toggle to true again
    toggle_unverified_allowed(&mut deps);
    assert!(unverified_allowed(&deps));
}

#[test]
fun test_toggle_unverified_allowed_from_true() {
    let mut deps = new_for_testing();
    deps.unverified_allowed = true;
    
    // Start with true
    assert!(unverified_allowed(&deps));
    
    // Toggle to false
    toggle_unverified_allowed(&mut deps);
    assert!(!unverified_allowed(&deps));
    
    // Toggle back to true
    toggle_unverified_allowed(&mut deps);
    assert!(unverified_allowed(&deps));
}

