/// The Extensions shared object tracks a list of verified and whitelisted packages.
/// These are the only packages that can be added as dependencies to an account if it disallows unverified packages.

module account_extensions::extensions;

// === Imports ===

use std::string::String;

// === Errors ===

const EExtensionNotFound: u64 = 0;
const EExtensionAlreadyExists: u64 = 1;
const ECannotRemoveAccountProtocol: u64 = 2;

// === Structs ===

/// A list of verified and whitelisted packages
public struct Extensions has key {
    id: UID,
    inner: vector<Extension>,
}

/// A package with a name and all authorized versions
public struct Extension has copy, drop, store {
    name: String,
    history: vector<History>,
}

/// The address and version of a package
public struct History has copy, drop, store {
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
        inner: vector::empty()  
    });
}

// === View functions ===

/// Returns the number of extensions in the list
public fun length(extensions: &Extensions): u64 {
    extensions.inner.length()
}

/// Returns the extension at the given index
public fun get_by_idx(extensions: &Extensions, idx: u64): &Extension {
    &extensions.inner[idx]
}

/// Returns the name of the extension
public fun name(extension: &Extension): String {
    extension.name
}

/// Returns the history of the extension
public fun history(extension: &Extension): vector<History> {
    extension.history
}

/// Returns the address of the history
public fun addr(history: &History): address {
    history.addr
}

/// Returns the version of the history
public fun version(history: &History): u64 {
    history.version
}

/// Returns the latest address and version for a given name
public fun get_latest_for_name(
    extensions: &Extensions, 
    name: String, 
): (address, u64) {
    let idx = get_idx_for_name(extensions, name);
    let history = extensions.inner[idx].history;
    let last_idx = history.length() - 1;

    (history[last_idx].addr, history[last_idx].version)
}

/// Returns true if the package (name, addr, version) is in the list
public fun is_extension(
    extensions: &Extensions, 
    name: String,
    addr: address,
    version: u64,
): bool {
    let opt_idx = extensions.inner.find_index!(|extension| extension.name == name);
    if (opt_idx.is_none()) return false;

    let idx = opt_idx.destroy_some();
    extensions.inner[idx].history.any!(|extension| extension.addr == addr) &&
    extensions.inner[idx].history.any!(|extension| extension.version == version)
}

// === Admin functions ===

/// Adds a package to the list
public fun add(extensions: &mut Extensions, _: &AdminCap, name: String, addr: address, version: u64) {    
    assert!(!extensions.inner.any!(|extension| extension.name == name), EExtensionAlreadyExists);
    assert!(!extensions.inner.any!(|extension| extension.history.any!(|h| h.addr == addr)), EExtensionAlreadyExists);
    let extension = Extension { name, history: vector[History { addr, version }] };
    extensions.inner.push_back(extension);
}

/// Removes a package from the list
public fun remove(extensions: &mut Extensions, _: &AdminCap, name: String) {
    let idx = extensions.get_idx_for_name(name);
    assert!(idx > 0, ECannotRemoveAccountProtocol);
    extensions.inner.remove(idx);
}

/// Adds a new version to the history of a package
public fun update(extensions: &mut Extensions, _: &AdminCap, name: String, addr: address, version: u64) {
    let idx = extensions.get_idx_for_name(name);
    assert!(!extensions.inner[idx].history.any!(|h| h.addr == addr), EExtensionAlreadyExists);
    extensions.inner[idx].history.push_back(History { addr, version });
}

public entry fun new_admin(_: &AdminCap, recipient: address, ctx: &mut TxContext) {
    transfer::public_transfer(AdminCap { id: object::new(ctx) }, recipient);
}

// === Private functions ===

fun get_idx_for_name(extensions: &Extensions, name: String): u64 {
    let opt = extensions.inner.find_index!(|extension| extension.name == name);
    assert!(opt.is_some(), EExtensionNotFound);
    opt.destroy_some()
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
        inner: vector[]
    }
}

#[test_only]
public fun add_for_testing(extensions: &mut Extensions, name: String, addr: address, version: u64) {    
    assert!(!extensions.inner.any!(|extension| extension.name == name), EExtensionAlreadyExists);
    assert!(!extensions.inner.any!(|extension| extension.history.any!(|h| h.addr == addr)), EExtensionAlreadyExists);
    let extension = Extension { name, history: vector[History { addr, version }] };
    extensions.inner.push_back(extension);
}

#[test_only]
public fun remove_for_testing(extensions: &mut Extensions, name: String) {
    let idx = extensions.get_idx_for_name(name);
    assert!(idx > 0, ECannotRemoveAccountProtocol);
    extensions.inner.remove(idx);
}

#[test_only]
public fun update_for_testing(extensions: &mut Extensions, name: String, addr: address, version: u64) {
    let idx = extensions.get_idx_for_name(name);
    assert!(!extensions.inner[idx].history.any!(|h| h.addr == addr), EExtensionAlreadyExists);
    extensions.inner[idx].history.push_back(History { addr, version });
}

#[test_only]
public fun new_for_testing_with_addrs(addr1: address, addr2: address, addr3: address, ctx: &mut TxContext): Extensions {
    Extensions {
        id: object::new(ctx),
        inner: vector[
            Extension { name: b"AccountProtocol".to_string(), history: vector[History { addr: addr1, version: 1 }] },
            Extension { name: b"AccountConfig".to_string(), history: vector[History { addr: addr2, version: 1 }] },
            Extension { name: b"AccountActions".to_string(), history: vector[History { addr: addr3, version: 1 }] }
        ]
    }
}

#[test_only]
public struct Witness() has drop;

#[test_only]
public fun witness(): Witness {
    Witness()
}

// === Unit Tests ===

#[test_only]
use sui::test_utils::destroy;
#[test_only]
use sui::test_scenario as ts;

#[test]
fun test_getters() {
    let extensions = new_for_testing_with_addrs(@0x0, @0x1, @0x2, &mut tx_context::dummy());

    // assertions
    assert!(extensions.is_extension(b"AccountProtocol".to_string(), @0x0, 1));
    assert!(extensions.is_extension(b"AccountConfig".to_string(), @0x1, 1));

    assert!(extensions.length() == 3);
    assert!(extensions.get_by_idx(0).name() == b"AccountProtocol".to_string());
    assert!(extensions.get_by_idx(0).history()[0].addr() == @0x0);
    assert!(extensions.get_by_idx(0).history()[0].version() == 1);
    assert!(extensions.get_by_idx(1).name() == b"AccountConfig".to_string());
    assert!(extensions.get_by_idx(1).history()[0].addr() == @0x1);
    assert!(extensions.get_by_idx(1).history()[0].version() == 1);
    assert!(extensions.get_by_idx(2).name() == b"AccountActions".to_string());
    assert!(extensions.get_by_idx(2).history()[0].addr() == @0x2);
    assert!(extensions.get_by_idx(2).history()[0].version() == 1);

    destroy(extensions);
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
    assert!(extensions.get_by_idx(3).name() == b"A".to_string());
    assert!(extensions.get_by_idx(3).history()[0].addr() == @0xA);
    assert!(extensions.get_by_idx(3).history()[0].version() == 1);
    assert!(extensions.get_by_idx(4).name() == b"B".to_string());
    assert!(extensions.get_by_idx(4).history()[1].addr() == @0x1B);
    assert!(extensions.get_by_idx(4).history()[1].version() == 2);
    assert!(extensions.get_by_idx(5).name() == b"C".to_string());
    assert!(extensions.get_by_idx(5).history()[2].addr() == @0x2C);
    assert!(extensions.get_by_idx(5).history()[2].version() == 3);
    // verify core deps didn't change    
    assert!(extensions.length() == 6);
    assert!(extensions.get_by_idx(0).name() == b"AccountProtocol".to_string());
    assert!(extensions.get_by_idx(0).history()[0].addr() == @0x0);
    assert!(extensions.get_by_idx(0).history()[0].version() == 1);
    assert!(extensions.get_by_idx(1).name() == b"AccountConfig".to_string());
    assert!(extensions.get_by_idx(1).history()[0].addr() == @0x1);
    assert!(extensions.get_by_idx(1).history()[0].version() == 1);
    assert!(extensions.get_by_idx(2).name() == b"AccountActions".to_string());
    assert!(extensions.get_by_idx(2).history()[0].addr() == @0x2);
    assert!(extensions.get_by_idx(2).history()[0].version() == 1);

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

#[test, expected_failure(abort_code = ECannotRemoveAccountProtocol)]
fun test_error_remove_account_protocol() {
    let mut extensions = new_for_testing_with_addrs(@0x0, @0x1, @0x2, &mut tx_context::dummy());
    let cap = AdminCap { id: object::new(&mut tx_context::dummy()) };
    extensions.remove(&cap, b"AccountProtocol".to_string());
    destroy(extensions);
    destroy(cap);
}

#[test, expected_failure(abort_code = EExtensionAlreadyExists)]
fun test_error_add_extension_name_already_exists() {
    let mut extensions = new_for_testing_with_addrs(@0x0, @0x1, @0x2, &mut tx_context::dummy());
    let cap = AdminCap { id: object::new(&mut tx_context::dummy()) };
    extensions.add(&cap, b"AccountProtocol".to_string(), @0xA, 1);
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
    extensions.add(&cap, b"A".to_string(), @0x0, 1);
    extensions.update(&cap, b"A".to_string(), @0x0, 2);
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