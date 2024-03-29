// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.18;

import "ds-test/test.sol";
import "./Vm.sol";


contract MStoreAndMLoadCaller {
    uint256 public constant memPtr = 0x80; // Memory location to use
    uint256 public constant expectedValueInMemory = 42;

    function storeAndLoadValueFromMemory() public pure returns (uint256) {
        assembly {
            mstore(memPtr, expectedValueInMemory)
        }

        uint256 result;
        assembly {
            result := mload(memPtr)
        }
        return result;
    }
}

contract FirstLayer {
    SecondLayer secondLayer;

    constructor(SecondLayer _secondLayer) public {
        secondLayer = _secondLayer;
    }

    function callSecondLayer() public view returns (uint256) {
        return secondLayer.endHere();
    }
}

contract SecondLayer {
    uint256 public constant endNumber = 123;

    function endHere() public view returns (uint256) {
        return endNumber;
    }
}

contract OutOfGas {
    uint256 dummyVal = 0;

    function consumeGas() public {
        dummyVal += 1;
    }

    function triggerOOG() public {
        bytes memory encodedFunctionCall = abi.encodeWithSignature("consumeGas()", "");
        uint notEnoughGas = 50;
        (bool success, ) = address(this).call{gas: notEnoughGas}(encodedFunctionCall);
        require(!success, "it should error out of gas");
    }
}

contract DebugTraceTest is DSTest {
    Vm constant cheats = Vm(HEVM_ADDRESS);
    /**
     * The goal of this test is to ensure the debug steps provide the correct OPCODE with its stack
     * and memory input used. The test checke MSTORE and MLOAD and ensure it records the expected
     * stack and memory inputs.
     */
    function testDebugTraceCanRecordOpcodeWithStackAndMemoryData() public {
        MStoreAndMLoadCaller testContract = new MStoreAndMLoadCaller();

        cheats.startDebugTraceRecording();

        testContract.storeAndLoadValueFromMemory();

        Vm.DebugStep[] memory steps = cheats.stopAndReturnDebugTraceRecording();

        bool mstoreCalled = false;
        bool mloadCalled = false;

        for (uint i = 0 ; i < steps.length ; i++) {
            if (steps[i].opcode == 0x52 /*MSTORE*/
                && steps[i].stack[0] == testContract.memPtr() // MSTORE offset
                && steps[i].stack[1] == testContract.expectedValueInMemory() // MSTORE val
            ) {
                mstoreCalled = true;
            }

            if (steps[i].opcode == 0x51 /*MLOAD*/
                && steps[i].stack[0] == testContract.memPtr() // MLOAD offset
            ) {
                mloadCalled = true;
            }
        }

        assertTrue(mstoreCalled);
        assertTrue(mloadCalled);
    }

    /**
     * This test tests that the cheatcode can correctly record the depth of the debug steps.
     * This is test by test -> FirstLayer -> SecondLayer and check that the
     * depth of the FirstLayer and SecondLayer are all as expected.
     */
    function testDebugTraceCanRecordDepth() public {
        SecondLayer second = new SecondLayer();
        FirstLayer first = new FirstLayer(second);

        cheats.startDebugTraceRecording();

        first.callSecondLayer();

        Vm.DebugStep[] memory steps = cheats.stopAndReturnDebugTraceRecording();

        bool goToDepthTwo = false;
        bool goToDepthThree = false;
        for (uint i = 0 ; i < steps.length ; i++) {
            if (steps[i].depth == 2) {
                assertTrue(steps[i].contractAddr == address(first), "must be first layer on depth 2");
                goToDepthTwo = true;
            }

            if (steps[i].depth == 3) {
                assertTrue(steps[i].contractAddr == address(second), "must be second layer on depth 3");
                goToDepthThree = true;
            }
        }
        assertTrue(goToDepthTwo && goToDepthThree, "must have been to both first and second layer");
    }


    /**
     * The goal of this test is to ensure it can return expected "instruction result".
     * It is tested with out of gas result here.
     */
    function testDebugTraceCanRecordInstructionResult() public {
        OutOfGas testContract = new OutOfGas();

        cheats.startDebugTraceRecording();

        testContract.triggerOOG();

        Vm.DebugStep[] memory steps = cheats.stopAndReturnDebugTraceRecording();

        bool isOOG = false;
        for (uint i = 0 ; i < steps.length ; i++) {
            // https://github.com/bluealloy/revm/blob/5a47ae0d2bb0909cc70d1b8ae2b6fc721ab1ca7d/crates/interpreter/src/instruction_result.rs#L23
            if (steps[i].instructionResult == 0x50) {
                isOOG = true;
            }
        }
        assertTrue(isOOG, "should have OOG instruction result");
    }

}
