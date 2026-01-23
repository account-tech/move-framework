/// The Extensions shared object tracks a list of verified and whitelisted packages.
/// These are the only packages that can be added as dependencies to an account if it disallows unverified packages.

module account_extensions::extensions;

// === Imports ===

use std::string::String;
use sui::table::{Self, Table};

// === Errors ===

const EExtensionNotFound: u64 = 0;
const EExtensionAlreadyExists: u64 = 1;

// === Structs ===

/// A list of verified and whitelisted packages
public struct Extensions has key {
    id: UID,
    by_name: Table<String, vector<PackageVersion>>,
    by_addr: Table<address, String>,
}

/// The address and version of a package
public struct PackageVersion has copy, drop, store {
    addr: address,
    version: u64,
}

/// A capability to add and remove extensions
public struct AdminCap has key, store {
    id: UID,
}

// === Public functions ===

fun init(ctx: &mut TxContext) {
    transfer::transfer(AdminCap { id: object::new(ctx) }, ctx.sender());
    transfer::share_object(Extensions { 
        id: object::new(ctx),
        by_name: table::new(ctx),
        by_addr: table::new(ctx),
    });
}

// === View functions ===

/// Returns the number of extensions in the list
public fun length(extensions: &Extensions): u64 {
    extensions.by_name.length()
}

/// Returns the package versions for a given name
public fun by_name(extensions: &Extensions, name: String): &vector<PackageVersion> {
    extensions.by_name.borrow(name)
}

/// Returns the name of the extension
public fun by_addr(extensions: &Extensions, addr: address): &String {
    extensions.by_addr.borrow(addr)
}

/// Returns the address of the PackageVersion
public fun addr(package_version: &PackageVersion): address {
    package_version.addr
}

/// Returns the version of the PackageVersion
public fun version(package_version: &PackageVersion): u64 {
    package_version.version
}

/// Returns the latest address and version for a given name
public fun get_latest_for_name(
    extensions: &Extensions, 
    name: String, 
): (address, u64) {
    let history = extensions.by_name.borrow(name);
    let package_version = history[history.length() - 1];

    (package_version.addr, package_version.version)
}

/// Returns true if the package (name, addr, version) is in the list
public fun is_extension(
    extensions: &Extensions, 
    name: String,
    addr: address,
    version: u64,
): bool {
    if (!extensions.by_name.contains(name)) return false;
    let history = extensions.by_name.borrow(name);
    let opt_idx = history.find_index!(|h| h.addr == addr);
    if (opt_idx.is_none()) return false;
    let idx = opt_idx.destroy_some();
    // check if the version exists for the name and address
    history[idx].version == version
}

// === Admin functions ===

/// Adds a new extension to the list 
public fun add(extensions: &mut Extensions, _: &AdminCap, name: String, addr: address, version: u64) {    
    assert!(!extensions.by_name.contains(name), EExtensionAlreadyExists);
    assert!(!extensions.by_addr.contains(addr), EExtensionAlreadyExists);
    let history = vector[PackageVersion { addr, version }];
    extensions.by_name.add(name, history);
    extensions.by_addr.add(addr, name);
}

/// Removes a package from the list
public fun remove(extensions: &mut Extensions, _: &AdminCap, name: String) {
    assert!(extensions.by_name.contains(name), EExtensionNotFound);
    let history = extensions.by_name.remove(name);
    history.do_ref!(|package_version| {
        if (extensions.by_addr.borrow(package_version.addr) == name) {
            extensions.by_addr.remove(package_version.addr);
        }
    });
}

/// Removes the version from the history of a package
public fun remove_version(extensions: &mut Extensions, _: &AdminCap, name: String, addr: address, version: u64) {
    let history = extensions.by_name.borrow_mut(name);
    let (exists, idx) = history.index_of(&PackageVersion { addr, version });
    assert!(exists, EExtensionNotFound);
    history.remove(idx);
}

/// Adds a new version to the history of a package
public fun update(extensions: &mut Extensions, _: &AdminCap, name: String, addr: address, version: u64) {
    assert!(extensions.by_name.contains(name), EExtensionNotFound);
    assert!(!extensions.by_addr.contains(addr), EExtensionAlreadyExists);
    extensions.by_name.borrow_mut(name).push_back(PackageVersion { addr, version });
    extensions.by_addr.add(addr, name);
}

public fun new_admin(_: &AdminCap, recipient: address, ctx: &mut TxContext) {
    transfer::public_transfer(AdminCap { id: object::new(ctx) }, recipient);
}

//**************************************************************************************************//
// Tests                                                                                            //
//**************************************************************************************************//

// === Test Helpers ===

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(ctx);
}

#[test_only]
public fun new_for_testing(ctx: &mut TxContext): Extensions {
    Extensions {
        id: object::new(ctx),
        by_name: table::new(ctx),
        by_addr: table::new(ctx),
    }
}

#[test_only]
public fun add_for_testing(extensions: &mut Extensions, name: String, addr: address, version: u64) {   
    assert!(!extensions.by_name.contains(name), EExtensionAlreadyExists);
    assert!(!extensions.by_addr.contains(addr), EExtensionAlreadyExists);
    let history = vector[PackageVersion { addr, version }];
    extensions.by_name.add(name, history);
    extensions.by_addr.add(addr, name);
}

#[test_only]
public fun remove_for_testing(extensions: &mut Extensions, name: String) {
    let history = extensions.by_name.remove(name);
    history.do_ref!(|package_version| {
        if (extensions.by_addr.borrow(package_version.addr) == name) {
            extensions.by_addr.remove(package_version.addr);
        }
    });
}

#[test_only]
public fun remove_version_for_testing(extensions: &mut Extensions, name: String, addr: address, version: u64) {
    let history = extensions.by_name.borrow_mut(name);
    let (exists, idx) = history.index_of(&PackageVersion { addr, version });
    assert!(exists, EExtensionNotFound);
    history.remove(idx);
}

#[test_only]
public fun update_for_testing(extensions: &mut Extensions, name: String, addr: address, version: u64) {
    assert!(!extensions.by_addr.contains(addr), EExtensionAlreadyExists);
    extensions.by_name.borrow_mut(name).push_back(PackageVersion { addr, version });
    extensions.by_addr.add(addr, name);
}

#[test_only]
public fun new_for_testing_with_addrs(addr1: address, addr2: address, addr3: address, ctx: &mut TxContext): Extensions {
    let mut extensions = new_for_testing(ctx);

    extensions.add_for_testing(b"account_protocol".to_string(), addr1, 1);
    extensions.add_for_testing(b"AccountConfig".to_string(), addr2, 1);
    extensions.add_for_testing(b"account_actions".to_string(), addr3, 1);

    extensions
}

#[test_only]
public struct Witness() has drop;

#[test_only]
public fun witness(): Witness {
    Witness()
}

// === Unit Tests ===

#[test_only]
use std::unit_test::destroy;
#[test_only]
use sui::test_scenario as ts;

#[test]
fun test_init() {
    let mut scenario = ts::begin(@0xCAFE);
    init(scenario.ctx());
    scenario.next_tx(@0xCAFE);

    let cap = scenario.take_from_sender<AdminCap>();
    let extensions = scenario.take_shared<Extensions>();

    destroy(cap);
    destroy(extensions);
    scenario.end();
}

#[test]
fun test_getters() {
    let extensions = new_for_testing_with_addrs(@0x0, @0x1, @0x2, &mut tx_context::dummy());

    // assertions
    assert!(extensions.is_extension(b"account_protocol".to_string(), @0x0, 1));
    assert!(extensions.is_extension(b"AccountConfig".to_string(), @0x1, 1));

    assert!(extensions.length() == 3);
    assert!(extensions.by_name(b"account_protocol".to_string())[0].addr() == @0x0);
    assert!(extensions.by_name(b"account_protocol".to_string())[0].version() == 1);
    assert!(extensions.by_name(b"AccountConfig".to_string())[0].addr() == @0x1);
    assert!(extensions.by_name(b"AccountConfig".to_string())[0].version() == 1);
    assert!(extensions.by_name(b"account_actions".to_string())[0].addr() == @0x2);
    assert!(extensions.by_name(b"account_actions".to_string())[0].version() == 1);

    destroy(extensions);
}

#[test]
fun test_get_latest_for_name() {
    let mut extensions = new_for_testing_with_addrs(@0x0, @0x1, @0x2, &mut tx_context::dummy());
    let cap = AdminCap { id: object::new(&mut tx_context::dummy()) };

    let (addr, version) = extensions.get_latest_for_name(b"account_protocol".to_string());
    assert!(addr == @0x0);
    assert!(version == 1);
    let (addr, version) = extensions.get_latest_for_name(b"AccountConfig".to_string());
    assert!(addr == @0x1);
    assert!(version == 1);
    let (addr, version) = extensions.get_latest_for_name(b"account_actions".to_string());
    assert!(addr == @0x2);
    assert!(version == 1);
    // update
    extensions.update(&cap, b"AccountConfig".to_string(), @0x11, 2);
    extensions.update(&cap, b"account_actions".to_string(), @0x21, 2);
    extensions.update(&cap, b"account_actions".to_string(), @0x22, 3);
    let (addr, version) = extensions.get_latest_for_name(b"account_protocol".to_string());
    assert!(addr == @0x0);
    assert!(version == 1);
    let (addr, version) = extensions.get_latest_for_name(b"AccountConfig".to_string());
    assert!(addr == @0x11);
    assert!(version == 2);
    let (addr, version) = extensions.get_latest_for_name(b"account_actions".to_string());
    assert!(addr == @0x22);
    assert!(version == 3);

    destroy(extensions);
    destroy(cap);
}

#[test]
fun test_is_extension() {
    let extensions = new_for_testing_with_addrs(@0x0, @0x1, @0x2, &mut tx_context::dummy());
    let cap = AdminCap { id: object::new(&mut tx_context::dummy()) };

    let (addr, version) = extensions.get_latest_for_name(b"account_protocol".to_string());
    assert!(addr == @0x0);
    assert!(version == 1);
    let (addr, version) = extensions.get_latest_for_name(b"AccountConfig".to_string());
    assert!(addr == @0x1);
    assert!(version == 1);
    let (addr, version) = extensions.get_latest_for_name(b"account_actions".to_string());
    assert!(addr == @0x2);
    assert!(version == 1);

    // correct extensions
    assert!(extensions.is_extension(b"account_protocol".to_string(), @0x0, 1));
    assert!(extensions.is_extension(b"AccountConfig".to_string(), @0x1, 1));
    assert!(extensions.is_extension(b"account_actions".to_string(), @0x2, 1));
    // incorrect names
    assert!(!extensions.is_extension(b"AccountProtoco".to_string(), @0x0, 1));
    assert!(!extensions.is_extension(b"AccountConfi".to_string(), @0x1, 1));
    assert!(!extensions.is_extension(b"AccountAction".to_string(), @0x2, 1));
    // incorrect addresses
    assert!(!extensions.is_extension(b"account_protocol".to_string(), @0x1, 1));
    assert!(!extensions.is_extension(b"AccountConfig".to_string(), @0x0, 1));
    assert!(!extensions.is_extension(b"account_actions".to_string(), @0x0, 1));
    // incorrect versions
    assert!(!extensions.is_extension(b"account_protocol".to_string(), @0x0, 2));
    assert!(!extensions.is_extension(b"AccountConfig".to_string(), @0x1, 2));
    assert!(!extensions.is_extension(b"account_actions".to_string(), @0x2, 2));

    destroy(extensions);
    destroy(cap);
}

#[test]
fun test_add_deps() {
    let mut extensions = new_for_testing(&mut tx_context::dummy());
    let cap = AdminCap { id: object::new(&mut tx_context::dummy()) };

    // add extension
    extensions.add(&cap, b"A".to_string(), @0xA, 1);
    extensions.add(&cap, b"B".to_string(), @0xB, 1);
    extensions.add(&cap, b"C".to_string(), @0xC, 1);
    // assertions
    assert!(extensions.is_extension(b"A".to_string(), @0xA, 1));
    assert!(extensions.is_extension(b"B".to_string(), @0xB, 1));
    assert!(extensions.is_extension(b"C".to_string(), @0xC, 1));

    destroy(extensions);
    destroy(cap);
}

#[test]
fun test_update_deps() {
    let mut extensions = new_for_testing_with_addrs(@0x0, @0x1, @0x2, &mut tx_context::dummy());
    let cap = AdminCap { id: object::new(&mut tx_context::dummy()) };

    // add extension (checked above)
    extensions.add(&cap, b"A".to_string(), @0xA, 1);
    extensions.add(&cap, b"B".to_string(), @0xB, 1);
    extensions.add(&cap, b"C".to_string(), @0xC, 1);
    // update deps
    extensions.update(&cap, b"B".to_string(), @0x1B, 2);
    extensions.update(&cap, b"C".to_string(), @0x1C, 2);
    extensions.update(&cap, b"C".to_string(), @0x2C, 3);
    // assertions
    assert!(extensions.by_name(b"A".to_string())[0].addr() == @0xA);
    assert!(extensions.by_name(b"A".to_string())[0].version() == 1);
    assert!(extensions.by_name(b"B".to_string())[1].addr() == @0x1B);
    assert!(extensions.by_name(b"B".to_string())[1].version() == 2);
    assert!(extensions.by_name(b"C".to_string())[2].addr() == @0x2C);
    assert!(extensions.by_name(b"C".to_string())[2].version() == 3);
    // verify core deps didn't change    
    assert!(extensions.length() == 6);
    assert!(extensions.by_name(b"account_protocol".to_string())[0].addr() == @0x0);
    assert!(extensions.by_name(b"account_protocol".to_string())[0].version() == 1);
    assert!(extensions.by_name(b"AccountConfig".to_string())[0].addr() == @0x1);
    assert!(extensions.by_name(b"AccountConfig".to_string())[0].version() == 1);
    assert!(extensions.by_name(b"account_actions".to_string())[0].addr() == @0x2);
    assert!(extensions.by_name(b"account_actions".to_string())[0].version() == 1);

    destroy(extensions);
    destroy(cap);
}

#[test]
fun test_remove_deps() {
    let mut extensions = new_for_testing_with_addrs(@0x0, @0x1, @0x2, &mut tx_context::dummy());
    let cap = AdminCap { id: object::new(&mut tx_context::dummy()) };

    // add extension (checked above)
    extensions.add(&cap, b"A".to_string(), @0xA, 1);
    extensions.add(&cap, b"B".to_string(), @0xB, 1);
    extensions.add(&cap, b"C".to_string(), @0xC, 1);
    // update deps
    extensions.update(&cap, b"B".to_string(), @0x1B, 2);
    extensions.update(&cap, b"C".to_string(), @0x1C, 2);
    extensions.update(&cap, b"C".to_string(), @0x2C, 3);
    // remove deps
    extensions.remove(&cap, b"A".to_string());
    extensions.remove(&cap, b"B".to_string());
    extensions.remove(&cap, b"C".to_string());
    // assertions
    assert!(!extensions.is_extension(b"A".to_string(), @0xA, 1));
    assert!(!extensions.is_extension(b"B".to_string(), @0xB, 1));
    assert!(!extensions.is_extension(b"B".to_string(), @0x1B, 2));
    assert!(!extensions.is_extension(b"C".to_string(), @0xC, 1));
    assert!(!extensions.is_extension(b"C".to_string(), @0x1C, 2));
    assert!(!extensions.is_extension(b"C".to_string(), @0x2C, 3));

    destroy(extensions);
    destroy(cap);
}

#[test]
fun test_new_admin() {
    let mut scenario = ts::begin(@0xCAFE);
    let cap = AdminCap { id: object::new(scenario.ctx()) };
    new_admin(&cap, @0xB0B, scenario.ctx());
    scenario.next_tx(@0xB0B);
    // check it exists
    let new_cap = scenario.take_from_sender<AdminCap>();
    destroy(cap);
    destroy(new_cap);
    ts::end(scenario);
}

#[test, expected_failure(abort_code = EExtensionAlreadyExists)]
fun test_error_add_extension_name_already_exists() {
    let mut extensions = new_for_testing_with_addrs(@0x0, @0x1, @0x2, &mut tx_context::dummy());
    let cap = AdminCap { id: object::new(&mut tx_context::dummy()) };
    extensions.add(&cap, b"account_protocol".to_string(), @0xA, 1);
    destroy(extensions);
    destroy(cap);
}

#[test, expected_failure(abort_code = EExtensionAlreadyExists)]
fun test_error_add_extension_address_already_exists() {
    let mut extensions = new_for_testing_with_addrs(@0x0, @0x1, @0x2, &mut tx_context::dummy());
    let cap = AdminCap { id: object::new(&mut tx_context::dummy()) };
    extensions.add(&cap, b"A".to_string(), @0x0, 1);
    destroy(extensions);
    destroy(cap);
}

#[test, expected_failure(abort_code = EExtensionNotFound)]
fun test_error_update_not_extension() {
    let mut extensions = new_for_testing_with_addrs(@0x0, @0x1, @0x2, &mut tx_context::dummy());
    let cap = AdminCap { id: object::new(&mut tx_context::dummy()) };
    extensions.update(&cap, b"A".to_string(), @0x0, 1);
    destroy(extensions);
    destroy(cap);
}

#[test, expected_failure(abort_code = EExtensionAlreadyExists)]
fun test_error_update_same_address() {
    let mut extensions = new_for_testing_with_addrs(@0x0, @0x1, @0x2, &mut tx_context::dummy());
    let cap = AdminCap { id: object::new(&mut tx_context::dummy()) };
    extensions.add(&cap, b"A".to_string(), @0xA, 1);
    extensions.update(&cap, b"A".to_string(), @0xA, 2);
    destroy(extensions);
    destroy(cap);
}

#[test, expected_failure(abort_code = EExtensionNotFound)]
fun test_error_remove_not_extension() {
    let mut extensions = new_for_testing_with_addrs(@0x0, @0x1, @0x2, &mut tx_context::dummy());
    let cap = AdminCap { id: object::new(&mut tx_context::dummy()) };
    extensions.remove(&cap, b"A".to_string());
    destroy(extensions);
    destroy(cap);
}