const ethers = require("ethers");

const hexlify = utf8str =>
  ethers.utils.hexlify(ethers.utils.toUtf8Bytes(utf8str));

const createPaddedMultihashSha256 = string => {
  const hash = ethers.utils.sha256(ethers.utils.toUtf8Bytes(string));
  const sha2_256 = ethers.utils.hexZeroPad("0x12", 8); // uint8
  const bits256 = ethers.utils.hexZeroPad(ethers.utils.hexlify(64), 8);

  const abiEncoder = new ethers.utils.AbiCoder();
  const multihash = abiEncoder.encode(
    ["uint8", "uint8", "bytes32"],
    [sha2_256, bits256, hash]
  );
  return multihash;
};

const createMultihashSha256 = string => {
  const hash = ethers.utils.sha256(ethers.utils.toUtf8Bytes(string));
  const sha2_256 = "0x12"; // uint8
  const bits256 = ethers.utils.hexlify(32);
  const multihash = sha2_256 + bits256.substr(2) + hash.substr(2);

  return multihash;
};

function createSelector(functionName, abiTypes) {
  const joinedTypes = abiTypes.join(",");
  const functionSignature = `${functionName}(${joinedTypes})`;

  const selector = ethers.utils.hexDataSlice(
    ethers.utils.keccak256(ethers.utils.toUtf8Bytes(functionSignature)),
    0,
    4
  );
  return selector;
}

function createInstanceAddressWithCallData(
  factoryContractAddress,
  logicContractAddress,
  sender,
  callData,
  nonce,
  salt
) {
  const abiEncoder = new ethers.utils.AbiCoder();

  const initCallData = abiEncoder.encode(
    ["address", "bytes"],
    [logicContractAddress, callData]
  );

  let spawnBytecode =
    "0x60806040526040516102953803806102958339818101604052604081101561002657600080fd5b81019080805190602001909291908051604051939291908464010000000082111561005057600080fd5b8382019150602082018581111561006657600080fd5b825186600182028301116401000000008211171561008357600080fd5b8083526020830192505050908051906020019080838360005b838110156100b757808201518184015260208101905061009c565b50505050905090810190601f1680156100e45780820380516001836020036101000a031916815260200191505b5060405250505060008273ffffffffffffffffffffffffffffffffffffffff16826040518082805190602001908083835b602083106101385780518252602082019150602081019050602083039250610115565b6001836020036101000a038019825116818451168082178552505050505050905001915050600060405180830381855af49150503d8060008114610198576040519150601f19603f3d011682016040523d82523d6000602084013e61019d565b606091505b50509050806101b0573d6000803e3d6000fd5b606069363d3d373d3d3d363d7360b01b846e5af43d82803e903d91602b57fd5bf360881b604051602001808475ffffffffffffffffffffffffffffffffffffffffffff191675ffffffffffffffffffffffffffffffffffffffffffff19168152600a018373ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff1660601b81526014018270ffffffffffffffffffffffffffffffffff191670ffffffffffffffffffffffffffffffffff19168152600f0193505050506040516020818303038152906040529050602d81602001f3fe";

  const initCodeHash = ethers.utils.solidityKeccak256(
    ["bytes", "bytes"],
    [spawnBytecode, initCallData]
  );

  if (!salt) {
    salt = ethers.utils.solidityKeccak256(
      ["address", "uint256"],
      [sender, nonce]
    );
  }

  const create2hash = ethers.utils.solidityKeccak256(
    ["bytes1", "address", "bytes32", "bytes32"],
    ["0xff", factoryContractAddress, salt, initCodeHash]
  );

  let instanceAddress = ethers.utils.getAddress(
    "0x" + create2hash.slice(12).substring(14)
  );
  return {
    callData,
    instanceAddress
  };
}

// the long, manual way of re-creating the instance address
function createInstanceAddress(
  factoryContractAddress,
  logicContractAddress,
  sender,
  initializeFunctionName,
  abiTypes,
  abiValues,
  nonce,
  salt
) {
  const callData = abiEncodeWithSelector(
    initializeFunctionName,
    abiTypes,
    abiValues
  );
  return createInstanceAddressWithCallData(
    factoryContractAddress,
    logicContractAddress,
    sender,
    callData,
    nonce,
    salt
  );
}

function createEip1167RuntimeCode(logicContractAddress) {
  return ethers.utils.solidityPack(
    ["bytes10", "address", "bytes15"],
    [
      "0x363d3d373d3d3d363d73",
      logicContractAddress,
      "0x5af43d82803e903d91602b57fd5bf3"
    ]
  );
}

const getLatestContractAdressFrom = async (provider, address) => {
  const nonce = await deployer.provider.getTransactionCount(address);
  const contractAddress = ethers.utils.getContractAddress({
    from: address,
    nonce: nonce - 1
  });
  return contractAddress;
};

/**
 * This function reflects the usage of abi.encodeWithSelector in Solidity.
 * It prepends the selector to the ABI-encoded values.
 *
 * @param {string} functionName
 * @param {Array<string>} abiTypes
 * @param {Array<any>} abiValues
 */
function abiEncodeWithSelector(functionName, abiTypes, abiValues) {
  const abiEncoder = new ethers.utils.AbiCoder();
  const initData = abiEncoder.encode(abiTypes, abiValues);
  const selector = createSelector(
    functionName,
    abiTypes
  );
  const encoded = selector + initData.slice(2);
  return encoded;
}

async function assertEvent(contract, txn, eventName, expectedArgs) {
  const receipt = await contract.verboseWaitForTransaction(txn);

  const eventLogs = utils.parseLogs(receipt, contract, eventName);

  // assert that the event with eventName only happened once
  assert.equal(eventLogs.length, 1);

  const [eventArgs] = eventLogs;

  assert.equal(eventArgs.length, expectedArgs.length);

  expectedArgs.forEach((expectedArg, index) =>
    assert.equal(eventArgs[index], expectedArg)
  );
}

module.exports = {
  hexlify,
  createInstanceAddress,
  createInstanceAddressWithCallData,
  createEip1167RuntimeCode,
  createSelector,
  createMultihashSha256,
  getLatestContractAdressFrom,
  abiEncodeWithSelector,
  assertEvent
};
