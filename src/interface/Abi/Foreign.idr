-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
||| Foreign Function Interface Bridge
|||
||| This module defines the raw FFI calls and their safe wrappers,
||| implemented in the Zig FFI layer.

module Abi.Foreign

import Abi.Types
import Abi.Layout

%default total

--------------------------------------------------------------------------------
-- Library Lifecycle
--------------------------------------------------------------------------------

||| Raw FFI call to initialize the library
%foreign "C:haec_init,libhaec"
prim__init : PrimIO Bits64

||| Raw FFI call to free library resources
%foreign "C:haec_free,libhaec"
prim__free : Bits64 -> PrimIO ()

||| Safe wrapper for initialization
export
init : IO (Maybe Handle)
init = do
  ptr <- primIO prim__init
  pure (createHandle ptr)

||| Safe wrapper for cleanup
export
free : Handle -> IO ()
free h = primIO (prim__free h.ptr)

--------------------------------------------------------------------------------
-- Core Operations
--------------------------------------------------------------------------------

||| Raw FFI call for main processing
%foreign "C:haec_process,libhaec"
prim__process : Bits64 -> Bits32 -> PrimIO Bits32

||| Safe wrapper with error handling
resultFromCode : Bits32 -> Result
resultFromCode 0 = Ok
resultFromCode 1 = Error
resultFromCode 2 = InvalidParam
resultFromCode 3 = Busy
resultFromCode _ = Error

||| Run the main operation and decode the C result code.
export
process : Handle -> Bits32 -> IO Result
process h input = do
  result <- primIO (prim__process h.ptr input)
  pure (resultFromCode result)

--------------------------------------------------------------------------------
-- Status and Metrics
--------------------------------------------------------------------------------

||| Get the current error description from the library
%foreign "C:haec_last_error,libhaec"
prim__getError : PrimIO (Ptr String)

||| Detailed error string helper
export
errorDescription : Result -> String
errorDescription Ok = "Success"
errorDescription Error = "Generic error"
errorDescription InvalidParam = "Invalid parameter"
errorDescription Busy = "Library is busy"

--------------------------------------------------------------------------------
-- Documentation
--------------------------------------------------------------------------------

||| Summary of ABI safety properties:
||| 1. All functions are total (total keyword enforced).
||| 2. Pointers are verified non-null before being wrapped in Handle.
||| 3. Memory layouts are proven C-ABI compliant in Abi.Layout.
||| 4. FFI boundary uses explicitly tagged types from Abi.Types.
public export
abiSafetyGuarantees : String
abiSafetyGuarantees = "Haec ABI: 4 proven safety properties for FFI integration"
