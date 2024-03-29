// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.23;

import {Test, console2} from "forge-std/Test.sol";
import {IPermit2} from "permit2/interfaces/IPermit2.sol";
import {ISignatureTransfer} from "permit2/interfaces/ISignatureTransfer.sol";
import {SignatureVerification} from "permit2/libraries/SignatureVerification.sol";
import {MockERC20} from "./mock/MockERC20.sol";
import {AddressBuilder} from "./utils/AddressBuilder.sol";
import {PermitSignature} from "./utils/PermitSignature.sol";
import {StructBuilder} from "./utils/StructBuilder.sol";
import {Verifier} from "../src/Verifier.sol";
import {SenderOrder, SenderOrderDetail} from "../src/OrderStructs.sol";

error InvalidNonce();

contract VeriferTest is Test, PermitSignature {
    using AddressBuilder for address[];

    struct Witness {
        address recipient;
    }

    struct InvalidWitness {
        uint256 amount;
    }

    string public constant PERMIT_BATCH_WITNESS_TRANSFER_TYPEHASH_STUB =
        "PermitBatchWitnessTransferFrom(TokenPermissions[] permitted,address spender,uint256 nonce,uint256 deadline,";

    bytes32 constant WITNESS_BATCH_TYPEHASH = keccak256(
        "PermitBatchWitnessTransferFrom(TokenPermissions[] permitted,address spender,uint256 nonce,uint256 deadline,Witness witness)Witness(address recipient)TokenPermissions(address token,uint256 amount)"
    );

    Verifier public verifier;
    MockERC20 public token1;
    MockERC20 public token2;

    address public permit2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    uint256 public DEFAULT_AMOUNT = 1 ether;
    uint256 public DEFAULT_BALANCE = 2 ether;

    address public sender;
    uint256 public senderPrivateKey;

    address recipient = address(0x1);
    address feeReceiver = address(0x2);

    bytes32 DOMAIN_SEPARATOR;

    function setUp() public {
        verifier = new Verifier(permit2);
        token1 = new MockERC20("token1", "TOKEN1");
        token2 = new MockERC20("token2", "TOKEN2");

        DOMAIN_SEPARATOR = verifier.permit2().DOMAIN_SEPARATOR();

        senderPrivateKey = 0x12341234;
        sender = vm.addr(senderPrivateKey);

        token1.mint(sender, DEFAULT_BALANCE);
        token2.mint(sender, DEFAULT_BALANCE);

        vm.startPrank(sender);
        token1.approve(permit2, type(uint256).max);
        token2.approve(permit2, type(uint256).max);
        vm.stopPrank();
    }

    function test_initialize() public {
        assertEq(address(verifier.permit2()), permit2);
        assertEq(token1.balanceOf(sender), DEFAULT_BALANCE);
        assertEq(token2.balanceOf(sender), DEFAULT_BALANCE);
    }

    function test_witnessTypehashes() public {
        assertEq(
            keccak256(abi.encodePacked(PERMIT_BATCH_WITNESS_TRANSFER_TYPEHASH_STUB, verifier.WITNESS_TYPE_STRING())),
            WITNESS_BATCH_TYPEHASH
        );
    }

    function test_execute_different_recipient_same_token() public {
        uint256 nonce = 0;
        Witness memory witnessData = Witness(recipient);
        bytes32 witness = keccak256(abi.encode(witnessData));
        address[] memory tokens = AddressBuilder.fill(1, address(token1)).push(address(token1));
        ISignatureTransfer.PermitBatchTransferFrom memory permit = getPermitTransferFrom(tokens, nonce, DEFAULT_AMOUNT);

        bytes memory sig = getPermitBatchWitnessSignature(
            permit, senderPrivateKey, WITNESS_BATCH_TYPEHASH, witness, DOMAIN_SEPARATOR, address(verifier)
        );

        address[] memory to = AddressBuilder.fill(1, address(recipient)).push(address(feeReceiver));
        ISignatureTransfer.SignatureTransferDetails[] memory toAmountPairs =
            StructBuilder.fillSigTransferDetails(DEFAULT_AMOUNT, to);

        SenderOrder memory senderOrder = _getSenderOrder(permit, toAmountPairs, sender, witness, sig);

        uint256 senderToken1Before = token1.balanceOf(sender);
        uint256 recipientToken1Before = token1.balanceOf(recipient);
        uint256 feeReceiverToken1Before = token1.balanceOf(feeReceiver);
        assertEq(recipientToken1Before, 0);
        assertEq(feeReceiverToken1Before, 0);

        verifier.execute(senderOrder);

        uint256 senderToken1After = token1.balanceOf(sender);
        uint256 recipientToken1After = token1.balanceOf(recipient);
        uint256 feeReceiverToken1After = token1.balanceOf(feeReceiver);
        assertEq(senderToken1After, senderToken1Before - DEFAULT_AMOUNT * 2);
        assertEq(recipientToken1After, recipientToken1Before + DEFAULT_AMOUNT);
        assertEq(feeReceiverToken1After, feeReceiverToken1Before + DEFAULT_AMOUNT);
    }

    function test_execute_different_recipient_with_random_nonce(uint256 _nonce) public {
        Witness memory witnessData = Witness(recipient);
        bytes32 witness = keccak256(abi.encode(witnessData));
        address[] memory tokens = AddressBuilder.fill(1, address(token1)).push(address(token1));
        ISignatureTransfer.PermitBatchTransferFrom memory permit = getPermitTransferFrom(tokens, _nonce, DEFAULT_AMOUNT);

        bytes memory sig = getPermitBatchWitnessSignature(
            permit, senderPrivateKey, WITNESS_BATCH_TYPEHASH, witness, DOMAIN_SEPARATOR, address(verifier)
        );

        address[] memory to = AddressBuilder.fill(1, address(recipient)).push(address(feeReceiver));
        ISignatureTransfer.SignatureTransferDetails[] memory toAmountPairs =
            StructBuilder.fillSigTransferDetails(DEFAULT_AMOUNT, to);

        SenderOrder memory senderOrder = _getSenderOrder(permit, toAmountPairs, sender, witness, sig);

        uint256 senderToken1Before = token1.balanceOf(sender);
        uint256 recipientToken1Before = token1.balanceOf(recipient);
        uint256 feeReceiverToken1Before = token1.balanceOf(feeReceiver);
        assertEq(recipientToken1Before, 0);
        assertEq(feeReceiverToken1Before, 0);

        verifier.execute(senderOrder);

        uint256 senderToken1After = token1.balanceOf(sender);
        uint256 recipientToken1After = token1.balanceOf(recipient);
        uint256 feeReceiverToken1After = token1.balanceOf(feeReceiver);
        assertEq(senderToken1After, senderToken1Before - DEFAULT_AMOUNT * 2);
        assertEq(recipientToken1After, recipientToken1Before + DEFAULT_AMOUNT);
        assertEq(feeReceiverToken1After, feeReceiverToken1Before + DEFAULT_AMOUNT);
    }

    function test_execute_different_recipient_with_random_amount(uint256 _amount) public {
        vm.assume(_amount / 2 == 0);

        MockERC20 token3 = new MockERC20("token3", "TOKEN3");
        token3.mint(sender, _amount);
        vm.prank(sender);
        token3.approve(permit2, type(uint256).max);

        uint256 nonce = 0;
        Witness memory witnessData = Witness(recipient);
        bytes32 witness = keccak256(abi.encode(witnessData));
        address[] memory tokens = AddressBuilder.fill(1, address(token3)).push(address(token3));
        ISignatureTransfer.PermitBatchTransferFrom memory permit = getPermitTransferFrom(tokens, nonce, DEFAULT_AMOUNT);

        bytes memory sig = getPermitBatchWitnessSignature(
            permit, senderPrivateKey, WITNESS_BATCH_TYPEHASH, witness, DOMAIN_SEPARATOR, address(verifier)
        );

        uint256 amountForEachReceiver = _amount / 2;
        address[] memory to = AddressBuilder.fill(1, address(recipient)).push(address(feeReceiver));
        ISignatureTransfer.SignatureTransferDetails[] memory toAmountPairs =
            StructBuilder.fillSigTransferDetails(amountForEachReceiver, to);

        SenderOrder memory senderOrder = _getSenderOrder(permit, toAmountPairs, sender, witness, sig);

        uint256 senderToken3Before = token3.balanceOf(sender);
        uint256 recipientToken3Before = token3.balanceOf(recipient);
        uint256 feeReceiverToken3Before = token3.balanceOf(feeReceiver);
        assertEq(recipientToken3Before, 0);
        assertEq(feeReceiverToken3Before, 0);

        verifier.execute(senderOrder);

        uint256 senderToken3After = token3.balanceOf(sender);
        uint256 recipientToken3After = token3.balanceOf(recipient);
        uint256 feeReceiverToken3After = token3.balanceOf(feeReceiver);
        assertEq(senderToken3After, senderToken3Before - amountForEachReceiver * 2);
        assertEq(recipientToken3After, recipientToken3Before + amountForEachReceiver);
        assertEq(feeReceiverToken3After, feeReceiverToken3Before + amountForEachReceiver);
    }

    // TODO: add test to transfer less tokens than defined.

    function test_execute_different_recipient_different_token() public {
        uint256 nonce = 0;
        Witness memory witnessData = Witness(recipient);
        bytes32 witness = keccak256(abi.encode(witnessData));
        address[] memory tokens = AddressBuilder.fill(1, address(token1)).push(address(token2));
        ISignatureTransfer.PermitBatchTransferFrom memory permit = getPermitTransferFrom(tokens, nonce, DEFAULT_AMOUNT);

        bytes memory sig = getPermitBatchWitnessSignature(
            permit, senderPrivateKey, WITNESS_BATCH_TYPEHASH, witness, DOMAIN_SEPARATOR, address(verifier)
        );

        address[] memory to = AddressBuilder.fill(1, address(recipient)).push(address(feeReceiver));
        ISignatureTransfer.SignatureTransferDetails[] memory toAmountPairs =
            StructBuilder.fillSigTransferDetails(DEFAULT_AMOUNT, to);

        SenderOrder memory senderOrder = _getSenderOrder(permit, toAmountPairs, sender, witness, sig);

        uint256 senderToken1Before = token1.balanceOf(sender);
        uint256 senderToken2Before = token2.balanceOf(sender);
        uint256 recipientToken1Before = token1.balanceOf(recipient);
        uint256 recipientToken2Before = token2.balanceOf(recipient);
        uint256 feeReceiverToken1Before = token1.balanceOf(feeReceiver);
        uint256 feeReceiverToken2Before = token2.balanceOf(feeReceiver);
        assertEq(recipientToken1Before, 0);
        assertEq(recipientToken2Before, 0);
        assertEq(feeReceiverToken1Before, 0);
        assertEq(feeReceiverToken2Before, 0);

        verifier.execute(senderOrder);

        uint256 senderToken1After = token1.balanceOf(sender);
        uint256 senderToken2After = token2.balanceOf(sender);
        uint256 recipientToken1After = token1.balanceOf(recipient);
        uint256 recipientToken2After = token2.balanceOf(recipient);
        uint256 feeReceiverToken1After = token1.balanceOf(feeReceiver);
        uint256 feeReceiverToken2After = token2.balanceOf(feeReceiver);
        assertEq(senderToken1After, senderToken1Before - DEFAULT_AMOUNT);
        assertEq(senderToken2After, senderToken2Before - DEFAULT_AMOUNT);
        assertEq(recipientToken1After, recipientToken1Before + DEFAULT_AMOUNT);
        assertEq(recipientToken2After, recipientToken2Before);
        assertEq(feeReceiverToken1After, feeReceiverToken1Before);
        assertEq(feeReceiverToken2After, feeReceiverToken2Before + DEFAULT_AMOUNT);
    }

    // tests related to the permit2
    function test_execute_with_invalid_sender_signature_length() public {
        uint256 nonce = 0;
        Witness memory witnessData = Witness(recipient);
        bytes32 witness = keccak256(abi.encode(witnessData));
        address[] memory tokens = AddressBuilder.fill(1, address(token1)).push(address(token1));
        ISignatureTransfer.PermitBatchTransferFrom memory permit = getPermitTransferFrom(tokens, nonce, DEFAULT_AMOUNT);

        bytes memory sig = getPermitBatchWitnessSignature(
            permit, senderPrivateKey, WITNESS_BATCH_TYPEHASH, witness, DOMAIN_SEPARATOR, address(verifier)
        );
        bytes memory sigExtra = bytes.concat(sig, bytes1(uint8(0)));
        assertEq(sigExtra.length, 66);

        address[] memory to = AddressBuilder.fill(1, address(recipient)).push(address(feeReceiver));
        ISignatureTransfer.SignatureTransferDetails[] memory toAmountPairs =
            StructBuilder.fillSigTransferDetails(DEFAULT_AMOUNT, to);

        SenderOrder memory senderOrder = _getSenderOrder(permit, toAmountPairs, sender, witness, sigExtra);

        vm.expectRevert(SignatureVerification.InvalidSignatureLength.selector);
        verifier.execute(senderOrder);
    }

    function test_execute_with_used_nonce() public {
        uint256 nonce = 0;
        Witness memory witnessData = Witness(recipient);
        bytes32 witness = keccak256(abi.encode(witnessData));
        address[] memory tokens = AddressBuilder.fill(1, address(token1)).push(address(token1));
        ISignatureTransfer.PermitBatchTransferFrom memory permit = getPermitTransferFrom(tokens, nonce, DEFAULT_AMOUNT);

        bytes memory sig = getPermitBatchWitnessSignature(
            permit, senderPrivateKey, WITNESS_BATCH_TYPEHASH, witness, DOMAIN_SEPARATOR, address(verifier)
        );

        address[] memory to = AddressBuilder.fill(1, address(recipient)).push(address(feeReceiver));
        ISignatureTransfer.SignatureTransferDetails[] memory toAmountPairs =
            StructBuilder.fillSigTransferDetails(DEFAULT_AMOUNT, to);

        SenderOrder memory senderOrder = _getSenderOrder(permit, toAmountPairs, sender, witness, sig);

        verifier.execute(senderOrder);

        vm.expectRevert(InvalidNonce.selector);
        verifier.execute(senderOrder);
    }

    function test_execute_with_different_length_of_PermitBatchTransferform_and_transferDetails() public {
        uint256 nonce = 0;
        Witness memory witnessData = Witness(recipient);
        bytes32 witness = keccak256(abi.encode(witnessData));
        address[] memory tokens = AddressBuilder.fill(1, address(token1)).push(address(token1));
        ISignatureTransfer.PermitBatchTransferFrom memory permit = getPermitTransferFrom(tokens, nonce, DEFAULT_AMOUNT);

        bytes memory sig = getPermitBatchWitnessSignature(
            permit, senderPrivateKey, WITNESS_BATCH_TYPEHASH, witness, DOMAIN_SEPARATOR, address(verifier)
        );

        address[] memory to = AddressBuilder.fill(1, address(recipient));
        ISignatureTransfer.SignatureTransferDetails[] memory toAmountPairs =
            StructBuilder.fillSigTransferDetails(DEFAULT_AMOUNT, to);

        SenderOrder memory senderOrder = _getSenderOrder(permit, toAmountPairs, sender, witness, sig);

        vm.expectRevert(ISignatureTransfer.LengthMismatch.selector);
        verifier.execute(senderOrder);
    }

    function test_execute_revert_if_typeHash_is_invalid() public {
        uint256 nonce = 0;
        Witness memory witnessData = Witness(recipient);
        bytes32 witness = keccak256(abi.encode(witnessData));
        address[] memory tokens = AddressBuilder.fill(1, address(token1)).push(address(token1));
        ISignatureTransfer.PermitBatchTransferFrom memory permit = getPermitTransferFrom(tokens, nonce, DEFAULT_AMOUNT);

        bytes memory sig = getPermitBatchWitnessSignature(
            permit, senderPrivateKey, "invalid typedHash", witness, DOMAIN_SEPARATOR, address(verifier)
        );

        address[] memory to = AddressBuilder.fill(1, address(recipient)).push(address(feeReceiver));
        ISignatureTransfer.SignatureTransferDetails[] memory toAmountPairs =
            StructBuilder.fillSigTransferDetails(DEFAULT_AMOUNT, to);

        SenderOrder memory senderOrder = _getSenderOrder(permit, toAmountPairs, sender, witness, sig);

        vm.expectRevert(SignatureVerification.InvalidSigner.selector);
        verifier.execute(senderOrder);
    }

    function test_execute_revert_if_willness_is_invalid() public {
        uint256 nonce = 0;
        Witness memory witnessData = Witness(recipient);
        bytes32 witness = keccak256(abi.encode(witnessData));
        address[] memory tokens = AddressBuilder.fill(1, address(token1)).push(address(token1));
        ISignatureTransfer.PermitBatchTransferFrom memory permit = getPermitTransferFrom(tokens, nonce, DEFAULT_AMOUNT);

        bytes memory sig = getPermitBatchWitnessSignature(
            permit, senderPrivateKey, WITNESS_BATCH_TYPEHASH, witness, DOMAIN_SEPARATOR, address(verifier)
        );

        address[] memory to = AddressBuilder.fill(1, address(recipient)).push(address(feeReceiver));
        ISignatureTransfer.SignatureTransferDetails[] memory toAmountPairs =
            StructBuilder.fillSigTransferDetails(DEFAULT_AMOUNT, to);

        InvalidWitness memory wrongData = InvalidWitness({amount: 1 ether});
        bytes32 invalidWitness = keccak256(abi.encode(wrongData));
        SenderOrder memory senderOrder = _getSenderOrder(permit, toAmountPairs, sender, invalidWitness, sig);

        vm.expectRevert(SignatureVerification.InvalidSigner.selector);
        verifier.execute(senderOrder);
    }

    function _getSenderOrder(
        ISignatureTransfer.PermitBatchTransferFrom memory _permit,
        ISignatureTransfer.SignatureTransferDetails[] memory _toAmountPairs,
        address _owner,
        bytes32 _witness,
        bytes memory _signature
    ) private pure returns (SenderOrder memory) {
        SenderOrder memory senderOrder =
            SenderOrder(abi.encode(SenderOrderDetail(_permit, _toAmountPairs, _owner, _witness)), _signature);

        return senderOrder;
    }
}
