#[test_only]
module account_protocol::deps_tests;

// === Imports ===

use sui::{
    test_utils::destroy,
    package,
};
use account_protocol::{
    deps,
    version,
    version_witness,
};
use account_extensions::extensions;

// === Tests ===

#[test]
fun test_deps_new_and_getters() {
    let extensions = extensions::new_for_testing_with_addrs(@account_protocol, @0x1, @0x2, &mut tx_context::dummy());

    let deps = deps::new(&extensions, false, vector[b"AccountProtocol".to_string(), b"AccountConfig".to_string()], vector[@account_protocol, @0x1], vector[1, 1]);
    // assertions
    deps.check(version::current());
    // deps getters
    assert!(deps.length() == 2);
    assert!(deps.contains_name(b"AccountProtocol".to_string()));
    assert!(deps.contains_addr(@account_protocol));
    // dep getters
    let dep = deps.get_by_name(b"AccountProtocol".to_string());
    assert!(dep.name() == b"AccountProtocol".to_string());
    assert!(dep.addr() == @account_protocol);
    assert!(dep.version() == 1);
    let dep = deps.get_by_addr(@account_protocol);
    assert!(dep.name() == b"AccountProtocol".to_string());
    assert!(dep.addr() == @account_protocol);
    assert!(dep.version() == 1);

    destroy(extensions);
}

#[test]
fun test_deps_new_latest_extensions() {
    let extensions = extensions::new_for_testing_with_addrs(@account_protocol, @0x1, @0x2, &mut tx_context::dummy());

    let deps = deps::new_latest_extensions(&extensions, vector[b"AccountProtocol".to_string(), b"AccountConfig".to_string()]);
    // assertions
    deps.check(version::current());
    // deps getters
    assert!(deps.length() == 2);
    assert!(deps.contains_name(b"AccountProtocol".to_string()));
    assert!(deps.contains_addr(@account_protocol));
    // dep getters
    let dep = deps.get_by_name(b"AccountProtocol".to_string());
    assert!(dep.name() == b"AccountProtocol".to_string());
    assert!(dep.addr() == @account_protocol);
    assert!(dep.version() == 1);
    let dep = deps.get_by_addr(@account_protocol);
    assert!(dep.name() == b"AccountProtocol".to_string());
    assert!(dep.addr() == @account_protocol);
    assert!(dep.version() == 1);

    destroy(extensions);
}

#[test]
fun test_deps_add_unverified_allowed() {
    let extensions = extensions::new_for_testing_with_addrs(@account_protocol, @0x1, @0x2, &mut tx_context::dummy());
    let cap = package::test_publish(@0xA.to_id(), &mut tx_context::dummy());

    let deps = deps::new(&extensions, true, vector[b"AccountProtocol".to_string(), b"Other".to_string()], vector[@account_protocol, @0xB], vector[1, 1]);
    // verify
    let dep = deps.get_by_name(b"Other".to_string());
    assert!(dep.name() == b"Other".to_string());
    assert!(dep.addr() == @0xB);
    assert!(dep.version() == 1);

    destroy(cap);
    destroy(extensions);
}

#[test, expected_failure(abort_code = deps::EDepsNotSameLength)]
fun test_error_deps_not_same_length() {
    let extensions = extensions::new_for_testing_with_addrs(@account_protocol, @0x1, @0x2, &mut tx_context::dummy());

    let _deps = deps::new(&extensions, false, vector[b"AccountProtocol".to_string()], vector[], vector[]);

    destroy(extensions);
}

#[test, expected_failure(abort_code = deps::EDepsNotSameLength)]
fun test_error_deps_not_same_length_bis() {
    let extensions = extensions::new_for_testing_with_addrs(@account_protocol, @0x1, @0x2, &mut tx_context::dummy());

    let _deps = deps::new(&extensions, false, vector[b"AccountProtocol".to_string()], vector[@account_protocol], vector[]);

    destroy(extensions);
}

#[test, expected_failure(abort_code = deps::EAccountProtocolMissing)]
fun test_error_deps_missing_account_protocol() {
    let extensions = extensions::new_for_testing_with_addrs(@account_protocol, @0x1, @0x2, &mut tx_context::dummy());

    let _deps = deps::new(&extensions, false, vector[b"AccountConfig".to_string()], vector[@0x1], vector[1]);

    destroy(extensions);
}

#[test, expected_failure(abort_code = deps::EAccountProtocolMissing)]
fun test_error_deps_missing_account_protocol_first_element() {
    let extensions = extensions::new_for_testing_with_addrs(@account_protocol, @0x1, @0x2, &mut tx_context::dummy());

    let _deps = deps::new(&extensions, false, vector[b"AccountActions".to_string(), b"AccountProtocol".to_string()], vector[@0x2, @account_protocol], vector[1, 1]);

    destroy(extensions);
}

#[test, expected_failure(abort_code = deps::EAccountConfigMissing)]
fun test_error_deps_missing_account_config_second_element() {
    let extensions = extensions::new_for_testing_with_addrs(@account_protocol, @0x1, @0x2, &mut tx_context::dummy());

    let _deps = deps::new(&extensions, false, vector[b"AccountProtocol".to_string(), b"AccountActions".to_string(), b"AccountConfig".to_string()], vector[@account_protocol, @0x2, @0x1], vector[1, 1, 1]);

    destroy(extensions);
}

#[test, expected_failure(abort_code = deps::ENotExtension)]
fun test_error_deps_add_not_extension_unverified_not_allowed() {
    let extensions = extensions::new_for_testing_with_addrs(@account_protocol, @0x1, @0x2, &mut tx_context::dummy());

    let _deps = deps::new(&extensions, false, vector[b"AccountProtocol".to_string(), b"Other".to_string()], vector[@account_protocol, @0xB], vector[1, 1]);

    destroy(extensions);
}

#[test, expected_failure(abort_code = deps::EDepAlreadyExists)]
fun test_error_deps_add_name_already_exists() {
    let extensions = extensions::new_for_testing_with_addrs(@account_protocol, @0x1, @0x2, &mut tx_context::dummy());
    let cap = package::test_publish(@0xA.to_id(), &mut tx_context::dummy());

    let _deps = deps::new(&extensions, false, vector[b"AccountProtocol".to_string(), b"AccountProtocol".to_string()], vector[@account_protocol, @0x1], vector[1, 1]);

    destroy(cap);
    destroy(extensions);
}

#[test, expected_failure(abort_code = deps::EDepAlreadyExists)]
fun test_error_deps_add_addr_already_exists() {
    let extensions = extensions::new_for_testing_with_addrs(@account_protocol, @0x1, @0x2, &mut tx_context::dummy());
    let cap = package::test_publish(@0xA.to_id(), &mut tx_context::dummy());

    let _deps = deps::new(&extensions, false, vector[b"AccountProtocol".to_string(), b"Other".to_string()], vector[@account_protocol, @account_protocol], vector[1, 1]);

    destroy(cap);
    destroy(extensions);
}

#[test, expected_failure(abort_code = deps::ENotDep)]
fun test_error_assert_is_dep() {
    let extensions = extensions::new_for_testing_with_addrs(@account_protocol, @0x1, @0x2, &mut tx_context::dummy());

    let deps = deps::new(&extensions, false, vector[b"AccountProtocol".to_string(), b"AccountConfig".to_string()], vector[@account_protocol, @0x1], vector[1, 1]);
    deps.check(version_witness::new_for_testing(@0xDE9));

    destroy(extensions);
}

#[test, expected_failure(abort_code = deps::EDepNotFound)]
fun test_error_name_not_found() {
    let extensions = extensions::new_for_testing_with_addrs(@account_protocol, @0x1, @0x2, &mut tx_context::dummy());

    let deps = deps::new(&extensions, false, vector[b"AccountProtocol".to_string(), b"AccountConfig".to_string()], vector[@account_protocol, @0x1], vector[1, 1]);
    deps.get_by_name(b"Other".to_string());

    destroy(extensions);
}

#[test, expected_failure(abort_code = deps::EDepNotFound)]
fun test_error_addr_not_found() {
    let extensions = extensions::new_for_testing_with_addrs(@account_protocol, @0x1, @0x2, &mut tx_context::dummy());

    let deps = deps::new(&extensions, false, vector[b"AccountProtocol".to_string(), b"AccountConfig".to_string()], vector[@account_protocol, @0x1], vector[1, 1]);
    deps.get_by_addr(@0xA);

    destroy(extensions);
}

#[test, expected_failure(abort_code = deps::EAccountProtocolMissing)]
fun test_error_new_latest_misses_account_protocol() {
    let extensions = extensions::new_for_testing_with_addrs(@account_protocol, @0x1, @0x2, &mut tx_context::dummy());

    let _deps = deps::new_latest_extensions(&extensions, vector[b"AccountConfig".to_string()]);

    destroy(extensions);
}

#[test, expected_failure(abort_code = deps::EDepAlreadyExists)]
fun test_error_new_latest_adds_account_protocol_twice() {
    let extensions = extensions::new_for_testing_with_addrs(@account_protocol, @0x1, @0x2, &mut tx_context::dummy());

    let _deps = deps::new_latest_extensions(&extensions, vector[b"AccountProtocol".to_string(), b"AccountProtocol".to_string()]);

    destroy(extensions);
}

#[test, expected_failure(abort_code = deps::EDepsNotSameLength)]
fun test_error_new_inner_not_same_length() {
    let extensions = extensions::new_for_testing_with_addrs(@account_protocol, @0x1, @0x2, &mut tx_context::dummy());

    let deps = deps::new_for_testing();
    let _deps = deps::new_inner(&extensions, &deps, vector[b"AccountProtocol".to_string()], vector[], vector[]);

    destroy(extensions);
}

#[test, expected_failure(abort_code = deps::EDepsNotSameLength)]
fun test_error_new_inner_not_same_length_bis() {
    let extensions = extensions::new_for_testing_with_addrs(@account_protocol, @0x1, @0x2, &mut tx_context::dummy());

    let deps = deps::new_for_testing();
    let _deps = deps::new_inner(&extensions, &deps, vector[b"AccountProtocol".to_string()], vector[@account_protocol], vector[]);

    destroy(extensions);
}

#[test, expected_failure(abort_code = deps::EAccountProtocolMissing)]
fun test_error_new_inner_missing_account_protocol() {
    let extensions = extensions::new_for_testing_with_addrs(@account_protocol, @0x1, @0x2, &mut tx_context::dummy());

    let deps = deps::new_for_testing();
    let _deps = deps::new_inner(&extensions, &deps, vector[b"AccountConfig".to_string()], vector[@0x1], vector[1]);

    destroy(extensions);
}

#[test, expected_failure(abort_code = deps::EAccountProtocolMissing)]
fun test_error_new_inner_missing_account_protocol_first_element() {
    let extensions = extensions::new_for_testing_with_addrs(@account_protocol, @0x1, @0x2, &mut tx_context::dummy());

    let deps = deps::new_for_testing();
    let _deps = deps::new_inner(&extensions, &deps, vector[b"AccountActions".to_string(), b"AccountProtocol".to_string()], vector[@0x2, @account_protocol], vector[1, 1]);

    destroy(extensions);
}

#[test, expected_failure(abort_code = deps::EAccountConfigMissing)]
fun test_error_new_inner_missing_account_config() {
    let extensions = extensions::new_for_testing_with_addrs(@account_protocol, @0x1, @0x2, &mut tx_context::dummy());

    let deps = deps::new_for_testing();
    let _deps = deps::new_inner(&extensions, &deps, vector[b"AccountProtocol".to_string(), b"AccountActions".to_string()], vector[@account_protocol, @0x2], vector[1, 1]);

    destroy(extensions);
}

#[test, expected_failure(abort_code = deps::EAccountConfigMissing)]
fun test_error_new_inner_missing_account_config_second_element() {
    let extensions = extensions::new_for_testing_with_addrs(@account_protocol, @0x1, @0x2, &mut tx_context::dummy());

    let deps = deps::new_for_testing();
    let _deps = deps::new_inner(&extensions, &deps, vector[b"AccountProtocol".to_string(), b"AccountActions".to_string(), b"AccountConfig".to_string()], vector[@account_protocol, @0x2, @0x1], vector[1, 1, 1]);

    destroy(extensions);
}

#[test, expected_failure(abort_code = deps::EAccountConfigMissing)]
fun test_error_new_inner_missing_account_config_unverified_disallowed_and_() {
    let extensions = extensions::new_for_testing_with_addrs(@account_protocol, @0x1, @0x2, &mut tx_context::dummy());

    let mut deps = deps::new_for_testing();
    deps.toggle_unverified_allowed_for_testing();
    let _deps = deps::new_inner(&extensions, &deps, vector[b"AccountProtocol".to_string(), b"AccountActions".to_string(), b"AccountConfig".to_string()], vector[@account_protocol, @0x2, @0x1], vector[1, 1, 1]);

    destroy(extensions);
}

#[test, expected_failure(abort_code = deps::ENotExtension)]
fun test_error_new_inner_add_not_extension_unverified_not_allowed() {
    let extensions = extensions::new_for_testing_with_addrs(@account_protocol, @0x1, @0x2, &mut tx_context::dummy());

    let deps = deps::new_for_testing();
    let _deps = deps::new_inner(&extensions, &deps, vector[b"AccountProtocol".to_string(), b"AccountConfig".to_string(), b"Other".to_string()], vector[@account_protocol, @0x1, @0xB], vector[1, 1, 1]);

    destroy(extensions);
}

#[test, expected_failure(abort_code = deps::EDepAlreadyExists)]
fun test_error_new_inner_add_name_already_exists() {
    let extensions = extensions::new_for_testing_with_addrs(@account_protocol, @0x1, @0x2, &mut tx_context::dummy());
    let cap = package::test_publish(@0xA.to_id(), &mut tx_context::dummy());

    let deps = deps::new_for_testing();
    let _deps = deps::new_inner(&extensions, &deps, vector[b"AccountProtocol".to_string(), b"AccountConfig".to_string(), b"AccountProtocol".to_string()], vector[@account_protocol, @0x1, @account_protocol], vector[1, 1, 1]);

    destroy(cap);
    destroy(extensions);
}

#[test, expected_failure(abort_code = deps::EDepAlreadyExists)]
fun test_error_new_inner_add_addr_already_exists() {
    let extensions = extensions::new_for_testing_with_addrs(@account_protocol, @0x1, @0x2, &mut tx_context::dummy());
    let cap = package::test_publish(@0xA.to_id(), &mut tx_context::dummy());

    let deps = deps::new_for_testing();
    let _deps = deps::new_inner(&extensions, &deps, vector[b"AccountProtocol".to_string(), b"AccountConfig".to_string(), b"AccountProtocol".to_string()], vector[@account_protocol, @0x1, @account_protocol], vector[1, 1, 1]);

    destroy(cap);
    destroy(extensions);
}
