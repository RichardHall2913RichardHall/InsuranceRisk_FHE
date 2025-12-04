// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { FHE, euint32, ebool } from "@fhevm/solidity/lib/FHE.sol";
import { SepoliaConfig } from "@fhevm/solidity/config/ZamaConfig.sol";

contract InsuranceRiskFHE is SepoliaConfig {
    struct EncryptedRiskData {
        uint256 id;
        euint32 encryptedCapital;  // Encrypted capital amount
        euint32 encryptedExposure; // Encrypted exposure value
        euint32 encryptedReinsurance; // Encrypted reinsurance data
        uint256 timestamp;
    }

    struct DecryptedRiskData {
        uint256 capital;
        uint256 exposure;
        uint256 reinsurance;
        bool isRevealed;
    }

    uint256 public dataCount;
    mapping(uint256 => EncryptedRiskData) public encryptedData;
    mapping(uint256 => DecryptedRiskData) public decryptedData;

    mapping(string => euint32) private encryptedAggregates;
    string[] private metricList;

    mapping(uint256 => uint256) private requestToDataId;

    event DataSubmitted(uint256 indexed id, uint256 timestamp);
    event DecryptionRequested(uint256 indexed id);
    event DataDecrypted(uint256 indexed id);

    modifier onlySubmitter(uint256 dataId) {
        // Placeholder for access control
        _;
    }

    function submitEncryptedData(
        euint32 encryptedCapital,
        euint32 encryptedExposure,
        euint32 encryptedReinsurance
    ) public {
        dataCount += 1;
        uint256 newId = dataCount;

        encryptedData[newId] = EncryptedRiskData({
            id: newId,
            encryptedCapital: encryptedCapital,
            encryptedExposure: encryptedExposure,
            encryptedReinsurance: encryptedReinsurance,
            timestamp: block.timestamp
        });

        decryptedData[newId] = DecryptedRiskData({
            capital: 0,
            exposure: 0,
            reinsurance: 0,
            isRevealed: false
        });

        emit DataSubmitted(newId, block.timestamp);
    }

    function requestDecryption(uint256 dataId) public onlySubmitter(dataId) {
        EncryptedRiskData storage dataItem = encryptedData[dataId];
        require(!decryptedData[dataId].isRevealed, "Already decrypted");

        bytes32[] memory ciphertexts = new bytes32[](3);
        ciphertexts[0] = FHE.toBytes32(dataItem.encryptedCapital);
        ciphertexts[1] = FHE.toBytes32(dataItem.encryptedExposure);
        ciphertexts[2] = FHE.toBytes32(dataItem.encryptedReinsurance);

        uint256 reqId = FHE.requestDecryption(ciphertexts, this.decryptCallback.selector);
        requestToDataId[reqId] = dataId;

        emit DecryptionRequested(dataId);
    }

    function decryptCallback(uint256 requestId, bytes memory cleartexts, bytes memory proof) public {
        uint256 dataId = requestToDataId[requestId];
        require(dataId != 0, "Invalid request");

        FHE.checkSignatures(requestId, cleartexts, proof);
        uint256[] memory results = abi.decode(cleartexts, (uint256[]));

        DecryptedRiskData storage dData = decryptedData[dataId];
        dData.capital = results[0];
        dData.exposure = results[1];
        dData.reinsurance = results[2];
        dData.isRevealed = true;

        for (uint i = 0; i < metricList.length; i++) {
            if (!FHE.isInitialized(encryptedAggregates[metricList[i]])) {
                encryptedAggregates[metricList[i]] = FHE.asEuint32(0);
            }
        }

        emit DataDecrypted(dataId);
    }

    function getDecryptedData(uint256 dataId) public view returns (uint256 capital, uint256 exposure, uint256 reinsurance, bool isRevealed) {
        DecryptedRiskData storage d = decryptedData[dataId];
        return (d.capital, d.exposure, d.reinsurance, d.isRevealed);
    }

    function getEncryptedAggregate(string memory metric) public view returns (euint32) {
        return encryptedAggregates[metric];
    }

    function requestAggregateDecryption(string memory metric) public {
        euint32 count = encryptedAggregates[metric];
        require(FHE.isInitialized(count), "Metric not found");

        bytes32[] memory ciphertexts = new bytes32[](1);
        ciphertexts[0] = FHE.toBytes32(count);

        uint256 reqId = FHE.requestDecryption(ciphertexts, this.decryptAggregateCallback.selector);
        requestToDataId[reqId] = uint256(keccak256(abi.encodePacked(metric)));
    }

    function decryptAggregateCallback(uint256 requestId, bytes memory cleartexts, bytes memory proof) public {
        uint256 metricHash = requestToDataId[requestId];
        string memory metric = getMetricFromHash(metricHash);
        FHE.checkSignatures(requestId, cleartexts, proof);
        uint32 count = abi.decode(cleartexts, (uint32));
    }

    function getMetricFromHash(uint256 hash) private view returns (string memory) {
        for (uint i = 0; i < metricList.length; i++) {
            if (uint256(keccak256(abi.encodePacked(metricList[i]))) == hash) {
                return metricList[i];
            }
        }
        revert("Metric not found");
    }
}