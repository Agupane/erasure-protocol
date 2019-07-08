pragma solidity ^0.5.0;

import "./helpers/openzeppelin-solidity/math/SafeMath.sol";
import "./helpers/openzeppelin-solidity/token/ERC20/ERC20Burnable.sol";
import "./helpers/HitchensUnorderedKeySet.sol";
import "./ErasureNext_Agreements.sol";
import "./ErasureNext_Escrow.sol";

// escrow the stake and allow for any counterparty to sign and activate the agreement

contract ErasureNext_SignedAgreement {

    using SafeMath for uint256;
    using HitchensUnorderedKeySetLib for HitchensUnorderedKeySetLib.Set;

    address public nmr;
    address public agreements;
    address public escrow;

    constructor(address _nmr, address _agreements, address _escrow) public {
        nmr = _nmr;
        agreements = _agreements;
        escrow = _escrow;
    }

    mapping (uint256 => SignedAgreement) public signedAgreements;
    HitchensUnorderedKeySetLib.Set agreementSet;

    struct SignedAgreement {
        address buyer;
        address seller;
        uint256 escrowID;
    }

    /* enum GriefType { CgtP, CltP, CeqP, InfGreif, NoGreif }
    enum State { Pending, Accepted, Ended } */

    event SignedAgreementCreated(uint256 agreementID, uint256 escrowID, address seller);

    modifier onlySeller(uint256 agreementID) {
        require(msg.sender == signedAgreements[agreementID].seller, 'only seller');
        _;
    }

    modifier onlyBuyer(uint256 agreementID) {
        require(msg.sender == signedAgreements[agreementID].buyer, 'only buyer');
        _;
    }

    // Agreement lifecycle //

    function createSignedAgreement(bytes memory metadata, uint256 sellerStake, bytes memory agreementArgs, uint256 escrowDeadline) public returns (uint256 agreementID, uint256 escrowID) {

        agreementID = encodedProposeAgreement(metadata, sellerStake, agreementArgs);

        require(IERC20(nmr).transferFrom(msg.sender, address(this), sellerStake));
        require(IERC20(nmr).approve(escrow, sellerStake));

        escrowID = ErasureNext_Escrow(escrow).createAndFund(
            address(this),
            nmr,
            sellerStake,
            escrowDeadline,
            metadata
        );

        signedAgreements[agreementID].seller = msg.sender;
        signedAgreements[agreementID].escrowID = escrowID;

        agreementSet.insert(bytes32(agreementID));

        emit SignedAgreementCreated(agreementID, escrowID, msg.sender);
    }

    function encodedProposeAgreement(bytes memory metadata, uint256 sellerStake, bytes memory agreementArgs) internal returns (uint256 agreementID) {
        (
            uint256 buyerStake,
            uint256 buyerGriefCost,
            uint256 sellerGriefCost,
            uint256 griefDeadline,
            ErasureNext_Agreements.GriefType buyerGriefType,
            ErasureNext_Agreements.GriefType sellerGriefType
        ) = abi.decode(agreementArgs, (uint256, uint256, uint256, uint256, ErasureNext_Agreements.GriefType, ErasureNext_Agreements.GriefType));

        agreementID = ErasureNext_Agreements(agreements).proposeAgreement(
            true,
            address(this),
            metadata,
            buyerStake,
            sellerStake,
            buyerGriefCost,
            sellerGriefCost,
            griefDeadline,
            buyerGriefType,
            sellerGriefType
        );
    }

    // Cannot use this version due to stack limit

    /* function createSignedAgreement(
        bytes memory metadata,
        uint256 buyerStake,
        uint256 sellerStake,
        uint256 buyerGriefCost,
        uint256 sellerGriefCost,
        uint256 griefDeadline,
        ErasureNext_Agreements.GriefType buyerGriefType,
        ErasureNext_Agreements.GriefType sellerGriefType,
        uint256 escrowDeadline
    ) public returns (uint256 agreementID, uint256 escrowID) {

        agreementID = ErasureNext_Agreements(agreements).proposeAgreement(
            true,
            address(this),
            metadata,
            buyerStake,
            sellerStake,
            buyerGriefCost,
            sellerGriefCost,
            griefDeadline,
            buyerGriefType,
            sellerGriefType
        );

        require(IERC20(nmr).transferFrom(msg.sender, address(this), sellerStake));
        require(IERC20(nmr).approve(escrow, sellerStake));

        escrowID = ErasureNext_Escrow(escrow).createAndFund(
            address(this),
            nmr,
            sellerStake,
            escrowDeadline,
            metadata
        );

        signedAgreements[agreementID].seller = msg.sender;
        signedAgreements[agreementID].escrowID = escrowID;

        agreementSet.insert(bytes32(agreementID));

        emit SignedAgreementCreated(agreementID, escrowID, msg.sender);
    } */

    function countersignAgreement(uint256 agreementID, bytes memory data) public {

        require(agreementSet.exists(bytes32(agreementID)), "signed agreement must exist");

        (,,,,uint256 buyerStake,uint256 sellerStake,,,,,,) = ErasureNext_Agreements(agreements).getAgreement(agreementID);

        require(IERC20(nmr).transferFrom(msg.sender, address(this), buyerStake));
        require(IERC20(nmr).approve(agreements, sellerStake.add(buyerStake)));

        ErasureNext_Escrow(escrow).submitData(signedAgreements[agreementID].escrowID, data);
        ErasureNext_Agreements(agreements).acceptAgreement(agreementID);

        signedAgreements[agreementID].buyer = msg.sender;
    }

    function cancelEscrow(uint256 agreementID) public onlySeller(agreementID) {

        uint256 escrowID = signedAgreements[agreementID].escrowID;

        uint256 escrowAmount = ErasureNext_Escrow(escrow).withdrawFunds(escrowID);
        ErasureNext_Agreements(agreements).cancelProposal(agreementID);

        require(IERC20(nmr).transfer(msg.sender, escrowAmount));
    }

    function endAgreement(uint256 agreementID) public onlySeller(agreementID) {

        require(agreementSet.exists(bytes32(agreementID)), "signed agreement must exist");

        (,,,,uint256 buyerStake,uint256 sellerStake,,,,,,) = ErasureNext_Agreements(agreements).getAgreement(agreementID);

        ErasureNext_Agreements(agreements).endAgreement(agreementID);

        require(IERC20(nmr).transfer(signedAgreements[agreementID].seller, sellerStake));
        require(IERC20(nmr).transfer(signedAgreements[agreementID].buyer, buyerStake));
    }

    // Griefing //

    function griefSeller(uint256 agreementID, uint256 punishment, bytes memory message) public {

        require(msg.sender == signedAgreements[agreementID].buyer, "only buyer");

        require(IERC20(nmr).transferFrom(msg.sender, address(this), punishment));
        require(IERC20(nmr).approve(agreements, punishment));

        ErasureNext_Agreements(agreements).griefSeller(agreementID, punishment, message);
    }

    function griefBuyer(uint256 agreementID, uint256 punishment, bytes memory message) public {

        require(msg.sender == signedAgreements[agreementID].seller, "only seller");

        require(IERC20(nmr).transferFrom(msg.sender, address(this), punishment));
        require(IERC20(nmr).approve(agreements, punishment));

        ErasureNext_Agreements(agreements).griefBuyer(agreementID, punishment, message);
    }

}
