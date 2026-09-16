{===============================================================================
  StdApp Components™

  Copyright © 2026-present tinyBigGAMES™ LLC
  All Rights Reserved.

  See LICENSE for license information

 -------------------------------------------------------------------------------

  StdApp.Resources - Shared resource strings

  Central repository of all user-facing message strings used across
  StdApp units. All error messages, warning text, and format strings
  are declared as resourcestring constants for localization readiness
  and clean separation from logic.

  Categories: severity names, error formats, fatal/IO messages,
  VFS messages, VirtualMemory messages.

  Dependencies: none
  Notes: Error code constants are defined in the unit of their concern,
    not here. This unit holds only the message text.
===============================================================================}

unit StdApp.Resources;

{$I StdApp.Defines.inc}

interface

resourcestring

  //--------------------------------------------------------------------------
  // Severity Names
  //--------------------------------------------------------------------------
  RSSeverityHint    = 'Hint';
  RSSeverityWarning = 'Warning';
  RSSeverityError   = 'Error';
  RSSeverityFatal   = 'Fatal';
  RSSeverityNote    = 'Note';
  RSSeverityUnknown = 'Unknown';

  //--------------------------------------------------------------------------
  // Error Format Strings
  //--------------------------------------------------------------------------
  RSErrorFormatSimple              = '%s %s: %s';
  RSErrorFormatWithLocation        = '%s: %s %s: %s';
  RSErrorFormatRelatedSimple       = '  %s: %s';
  RSErrorFormatRelatedWithLocation = '  %s: %s: %s';

  //--------------------------------------------------------------------------
  // Fatal / I/O Messages
  //--------------------------------------------------------------------------
  RSFatalFileNotFound  = 'File not found: ''%s''';
  RSFatalFileReadError = 'Cannot read file ''%s'': %s';
  RSFatalInternalError = 'Internal error: %s';

  //--------------------------------------------------------------------------
  // VFS Messages
  //--------------------------------------------------------------------------
  RSVFSOpenFileFailed      = 'Failed to open file: ''%s''';
  RSVFSInvalidMagic        = 'Invalid VFS archive magic signature';
  RSVFSInvalidVersion      = 'Unsupported VFS archive version: %d';
  RSVFSTruncated           = 'VFS archive is truncated or corrupt';
  RSVFSNotOpen             = 'VFS archive is not open';
  RSVFSEntryNotFound       = 'Entry not found in VFS: ''%s''';
  RSVFSScanDirFailed       = 'Failed to scan directory: ''%s''';
  RSVFSEmptyDirectory      = 'Source directory contains no files: ''%s''';
  RSVFSSourceOpenFailed    = 'Failed to open source file for packing: ''%s''';
  RSVFSException           = 'Unexpected exception in VFS: %s';

  //--------------------------------------------------------------------------
  // VirtualMemory Messages
  //--------------------------------------------------------------------------
  RSVMAllocSizeZero          = 'Cannot allocate a zero-size buffer';
  RSVMCreateMappingFailed    = 'CreateFileMapping failed (error %d)';
  RSVMMappingNameExists      = 'Mapping name "%s" already exists';
  RSVMMapViewFailed          = 'MapViewOfFile failed (error %d)';
  RSVMAllocException         = 'Allocate exception: %s';
  RSVMSharedNameEmpty        = 'OpenShared: mapping name must not be empty';
  RSVMOpenMappingFailed      = 'OpenFileMapping failed for "%s" (error %d)';
  RSVMMapViewNamedFailed     = 'MapViewOfFile failed for "%s" (error %d)';
  RSVMSharedException        = 'OpenShared exception for "%s": %s';
  RSVMUseAllocate            = 'Use Allocate() for anonymous buffers, not Open()';
  RSVMOpenFileFailed         = 'Cannot open file "%s" (error %d)';
  RSVMFileEmpty              = 'File "%s" is empty -- cannot memory-map';
  RSVMCreateMappingNamedFailed = 'CreateFileMapping failed for "%s" (error %d)';
  RSVMOpenException          = 'Open exception for "%s": %s';
  RSVMLoadAlignmentFailed    = 'File size (%d) is not aligned to element size (%d)';
  RSVMLoadException          = 'LoadFromFile exception for "%s": %s';
  RSVMFlushFailed            = 'FlushViewOfFile failed (error %d)';
  RSVMGrowNotAnonymous       = 'Grow is only valid for anonymous (vmAllocate) buffers';
  RSVMGrowNotShared          = 'Grow is not valid for shared consumer mappings';
  RSVMGrowMappingFailed      = 'Grow: CreateFileMapping failed (error %d)';
  RSVMGrowMapViewFailed      = 'Grow: MapViewOfFile failed (error %d)';
  RSVMGrowException          = 'Grow exception: %s';

  //--------------------------------------------------------------------------
  // Crypto Messages
  //--------------------------------------------------------------------------
  RSCryFileNotFound  = 'File not found: %s';
  RSCryFileError     = 'File error: %s';
  RSCryRandomFailed  = 'Secure random generation failed (BCryptGenRandom)';
  RSCryNoSecretKey   = 'No secret key present in key pair';
  RSCryNoPublicKey   = 'No public key present in key pair';
  RSCryBadKeyFile    = 'Invalid or unrecognized key data: %s';
  RSCryBadSigFile    = 'Invalid signature file: %s';
  RSCryKeyIdMismatch = 'Signature key id does not match the public key: %s';
  RSCryVerifyFailed  = 'Signature verification FAILED for: %s';
  RSCrySecKeyComment     = 'apppacker secret key %s';
  RSCrySigDefaultComment = 'signature from apppacker secret key %s';

  //--------------------------------------------------------------------------
  // Packer Messages
  //--------------------------------------------------------------------------
  RSPakManifestNotFound = 'Manifest not found: %s';
  RSPakParseError       = 'Manifest parse error at line %d: %s';
  RSPakNoOutput         = 'Manifest is missing the output: key';
  RSPakSourceMissing    = 'Source directory not found: %s';
  RSPakSourceScan       = 'scan: %s (prefix: %s)';
  RSPakMatched          = 'matched: %d file(s)';
  RSPakNoFiles          = 'Nothing to pack (no files matched include/exclude rules)';
  RSPakAdd              = 'add: %s';
  RSPakDone             = 'done: %d file(s) -> %s';
  RSPakChecksum         = 'checksum: %s';
  RSPakSigned           = 'signed: %s';
  RSPakSecKeyInArchive  = 'FATAL: the configured secret key file is matched by include rules: %s';
  RSPakZipError         = 'Archive build failed: %s';
  RSPakNoSecKey         = 'sign: block present but seckey: is missing';

  //--------------------------------------------------------------------------
  // AppPacker CLI Messages
  //--------------------------------------------------------------------------
  RSCliBanner = 'AppPacker™ %s - manifest-driven release packer';
  RSCliUsage = 'Usage:'#13#10 +
    '  AppPacker <manifest.yml>'#13#10 +
    '  AppPacker pack <manifest.yml>'#13#10 +
    '  AppPacker keygen <basepath>'#13#10 +
    '  AppPacker verify <file> <pubkey-file-or-string>';
  RSCliPacking       = 'packing: %s %s';
  RSCliKeyExists     = 'REFUSED: secret key already exists, will not overwrite: %s';
  RSCliKeygenDone    = 'keypair written: %s / %s';
  RSCliKeyId         = 'key id: %s';
  RSCliPubKey        = 'public key: %s';
  RSCliKeyBackupHint = 'BACK UP the .key file now. It is NOT encrypted. Keep it OUTSIDE any repo.';
  RSCliVerifyOk      = 'verified OK: %s';

  //--------------------------------------------------------------------------
  // Waskal - Lexer
  //--------------------------------------------------------------------------
  RSLexUnexpectedChar      = 'Unexpected character: %s';
  RSLexUnterminatedString  = 'Unterminated string literal';
  RSLexInvalidNumber       = 'Invalid number format';
  RSLexUnterminatedComment = 'Unterminated block comment';
  RSLexInvalidEscape       = 'Invalid escape sequence: \%s';
  RSLexInvalidHexEscape    = 'Invalid hex escape sequence';
  RSLexInvalidHexLiteral   = 'Invalid hexadecimal literal';
  RSLexInvalidCharacter    = 'Invalid character: ''%s''';
  RSLexExpected            = 'Expected %s but found ''%s''';

  //--------------------------------------------------------------------------
  // Waskal - Parser
  //--------------------------------------------------------------------------
  RSParUnexpectedToken       = 'Unexpected token in declarations: %s';
  RSParExpectedEnd           = 'Expected "end" to close "%s" started at line %d';
  RSParInvalidModuleKind     = 'Invalid module kind: %s (expected exe, lib, unit)';
  RSParExpectedModuleKind    = 'Expected module kind (exe, lib, unit)';
  RSParDuplicateImport       = 'Duplicate import: %s';
  RSParExpectedImportName    = 'Expected import module name';
  RSParInvalidStatement      = 'Invalid statement: %s';
  RSParInvalidExpression     = 'Invalid expression: %s';
  RSParExpectedIdentifier    = 'Expected module name identifier';
  RSParExpectedToOrDownTo    = 'Expected "to" or "downto"';
  RSParExpectedAfterForward  = 'Expected type or routine after forward';
  RSParDefineNeedsIdent      = '@define requires an identifier argument';
  RSParUndefNeedsIdent       = '@undef requires an identifier argument';
  RSParIfdefNeedsIdent       = '@ifdef requires an identifier argument';
  RSParIfndefNeedsIdent      = '@ifndef requires an identifier argument';
  RSParElseifNoMatch         = '@elseif without matching @ifdef';
  RSParElseNoMatch           = '@else without matching @ifdef';
  RSParEndifNoMatch          = '@endif without matching @ifdef';
  RSParUnterminatedIfdef     = 'Unterminated @ifdef/@ifndef block';

  //--------------------------------------------------------------------------
  // Waskal - Semantics
  //--------------------------------------------------------------------------
  RSSemUndeclaredIdentifier   = 'Undeclared identifier: %s';
  RSSemUndeclaredType         = 'Undeclared type: %s';
  RSSemDuplicateDeclaration   = 'Duplicate declaration: %s';
  RSSemBreakOutsideLoop       = 'Break/continue outside of loop';
  RSSemUnresolvedForwardType  = 'Unresolved forward type: %s';
  RSSemUnresolvedForwardRout  = 'Unresolved forward routine: %s';
  RSSemForwardTypeNotType     = 'Forward type "%s" does not resolve to a type declaration';
  RSSemForwardRoutNotRout     = 'Forward routine "%s" does not resolve to a routine declaration';
  RSSemExtVarMissingLib       = 'External variable missing library name';
  RSSemExtVarMissingName      = 'External variable missing symbol name';
  RSSemExtRoutMissingLib      = 'External routine missing library name';
  RSSemExtRoutMissingName     = 'External routine missing symbol name';
  RSSemChoicesNoMember        = 'Choices type has no member "%s"';
  RSSemNoFieldFound           = 'No field "%s" found';
  RSSemExeNeedsMainBody       = 'Executable module must have a main body';
  RSSemUnitForbidsMainBody    = 'Unit module must not have a main body';
  RSSemNoMatchingOverload     = 'No matching overload for ''%s''';
  RSSemArgCountMismatch       = 'Routine ''%s'' expects %d argument(s), got %d';
  RSSemArgCountAtLeast        = 'Routine ''%s'' expects at least %d argument(s), got %d';
  RSSemForwardMismatch        = 'Forward declaration of ''%s'' does not match its implementation: %s';
  RSSemVarArgsOutside         = 'varargs is only valid inside a variadic routine';

  // Emitter (Waskal.Emitter)
  RSEmtRuntimeNotFound        = 'runtime.wat not found: %s';
  RSEmtRuntimeReadFailed      = 'Failed to read runtime.wat: %s';

  //--------------------------------------------------------------------------
  // Waskal - Build
  //--------------------------------------------------------------------------
  RSBldWatWriteFailed        = 'Failed to write .wat file: %s';
  RSBldWasmOptNotFound       = 'wasm-opt not found: %s';
  RSBldWasmOptStartFailed    = 'wasm-opt failed to start: %s';
  RSBldWasmOptNoOutput       = 'wasm-opt produced no output: %s';
  RSBldWasmMergeNotFound     = 'wasm-merge not found: %s';
  RSBldWasmMergeStartFailed  = 'wasm-merge failed to start: %s';
  RSBldWasmMergeError        = 'wasm-merge: %s';
  RSBldWasmMergeExitCode     = 'wasm-merge exited with code %d';
  RSBldWasmMergeNoOutput     = 'wasm-merge produced no output: %s';
  RSBldWasmOptError          = 'wasm-opt: %s';
  RSBldWasmOptFailedNoOut    = 'wasm-opt failed with no output';
  RSBldJsRuntimeNotFound     = 'JS runtime not found: %s';
  RSBldExternalJsNotFound    = 'External JS file not found: ''%s''';
  RSBldEsbuildNotFound       = 'esbuild not found: %s -- skipping minification';
  RSBldJsTempWriteFailed     = 'Failed to write JS temp file: %s';
  RSBldEsbuildStartFailed    = 'esbuild failed to start: %s -- skipping minification';
  RSBldEsbuildExitCode       = 'esbuild failed with exit code %d -- skipping minification';
  RSBldEsbuildNoOutput       = 'esbuild produced no output -- skipping minification';
  RSBldMinifiedJsReadFailed  = 'Failed to read minified JS: %s';
  RSBldDuplicateAssetKey     = 'Duplicate asset key: ''%s''';
  RSBldAssetFileNotFound     = 'Asset file not found: ''%s''';
  RSBldAssetDirNotFound      = 'Asset directory not found: ''%s''';
  RSBldAssetBaseNotInPath    = 'Asset base folder ''%s'' is not a path segment of ''%s''';
  RSBldAssetRuntimeNotFound  = 'Asset runtime JS not found: %s';
  RSBldHtmlTemplateNotFound  = 'HTML template not found: %s';
  RSBldFaviconNotFound       = 'Favicon file not found: ''%s''';
  RSBldOutputWriteFailed     = 'Failed to write output: %s';
  RSBldNoWatSource           = 'No .wat source to build';
  RSBldWasmCopyFailed        = 'Failed to copy .wasm to output: %s';
  RSBldOnlyExeCanRun         = 'Only exe modules can be run';
  RSBldOutputNotFound        = 'Output file not found: %s';

implementation

end.
