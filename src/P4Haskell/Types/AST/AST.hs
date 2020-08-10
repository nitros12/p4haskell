-- | Represents the P4 AST in haskellmodule P4Haskell.Types.AST
module P4Haskell.Types.AST.AST
 where

import           Control.Monad.Error.Class          ( throwError )

import qualified Generics.SOP as GS

import           Data.Generics.Sum.Typed

import           P4Haskell.Types.AST.Annotation
import           P4Haskell.Types.AST.Core
import           P4Haskell.Types.AST.DeclarationID
import           P4Haskell.Types.AST.DecompressJSON
import           P4Haskell.Types.AST.Expression
import           P4Haskell.Types.AST.Statement
import           P4Haskell.Types.AST.Method
import           P4Haskell.Types.AST.Parameter
import           P4Haskell.Types.AST.Types
import           P4Haskell.Types.AST.ActionList

import           Prelude

import           Polysemy                           hiding ( Member )

import           Waargonaut
import qualified Waargonaut.Decode                  as D
import qualified Waargonaut.Decode.Error            as D


astDecoder :: DecompressC r => D.Decoder (Sem r) P4Program
astDecoder = D.withCursor $ \c -> do
  o       <- D.down c
  objects <- D.fromKey "objects" (parseVectorPure topLevelDecoder) o
  pure $ P4Program objects

newtype P4Program = P4Program
  { objects :: [TopLevel]
  }
  deriving ( Show, Generic )

data TopLevel
  = TypeDecl'TopLevelTypeDecl TopLevelTypeDecl
  | Method'TopLevel Method
  | DeclarationMatchKind'TopLevel DeclarationMatchKind
  | P4Parser'TopLevel P4Parser
  | P4Control'TopLevel P4Control
  | DeclarationInstance'TopLevel DeclarationInstance
  deriving ( Show, Generic )

topLevelDecoder :: DecompressC r => D.Decoder (Sem r) TopLevel
topLevelDecoder = D.withCursor $ \c -> do
  res <- topLevelTypeDeclDecoderInner c
  case res of
    Just x  -> pure $ (_Typed @TopLevelTypeDecl #) x
    Nothing -> do
      nodeType <- currentNodeType c

      case nodeType of
        "Method"                    -> (_Typed @Method #)                    <$> tryDecoder parseMethod c
        "Declaration_MatchKind"     -> (_Typed @DeclarationMatchKind #)      <$> tryDecoder parseDeclarationMatchKind c
        "P4Parser"                  -> (_Typed @P4Parser #)                  <$> tryDecoder parseP4Parser c
        "P4Control"                 -> (_Typed @P4Control #)                 <$> tryDecoder parseP4Control c
        "Declaration_Instance"      -> (_Typed @DeclarationInstance #)       <$> tryDecoder parseDeclarationInstance c
        _ -> throwError . D.ParseFailed $ "invalid node type for TopLevel: " <> nodeType

data TopLevelTypeDecl
  = TypeError'TopLevelTypeDecl TypeError
  | TypeExtern'TopLevelTypeDecl TypeExtern
  | TypeParser'TopLevelTypeDecl TypeParser
  | TypeControl'TopLevelTypeDecl TypeControl
  | TypePackage'TopLevelTypeDecl TypePackage
  | TypeTypedef'TopLevelTypeDecl TypeTypedef
  | TypeHeader'TopLevelTypeDecl TypeHeader
  | TypeStruct'TopLevelTypeDecl TypeStruct
  | TypeEnum'TopLevelTypeDecl TypeEnum
  deriving ( Show, Generic, GS.Generic )

topLevelTypeDeclDecoderInner :: DecompressC r => D.JCurs -> D.DecodeResult (Sem r) (Maybe TopLevelTypeDecl)
topLevelTypeDeclDecoderInner c = do
  nodeType <- currentNodeType c

  case nodeType of
    "Type_Error"                -> Just . (_Typed @TypeError #)                 <$> tryDecoder parseTypeError c
    "Type_Extern"               -> Just . (_Typed @TypeExtern #)                <$> tryDecoder parseTypeExtern c
    "Type_Parser"               -> Just . (_Typed @TypeParser #)                <$> tryDecoder parseTypeParser c
    "Type_Control"              -> Just . (_Typed @TypeControl #)               <$> tryDecoder parseTypeControl c
    "Type_Package"              -> Just . (_Typed @TypePackage #)               <$> tryDecoder parseTypePackage c
    "Type_Typedef"              -> Just . (_Typed @TypeTypedef #)               <$> tryDecoder parseTypeTypedef c
    "Type_Header"               -> Just . (_Typed @TypeHeader #)                <$> tryDecoder parseTypeHeader c
    "Type_Struct"               -> Just . (_Typed @TypeStruct #)                <$> tryDecoder parseTypeStruct c
    "Type_Enum"                 -> Just . (_Typed @TypeEnum #)                  <$> tryDecoder parseTypeEnum c
    _ -> pure Nothing

topLevelTypeDeclDecoder :: DecompressC r => D.Decoder (Sem r) TopLevelTypeDecl
topLevelTypeDeclDecoder = D.withCursor $ \c -> do
  res <- topLevelTypeDeclDecoderInner c
  case res of
    Just x  -> pure x
    Nothing -> do
        nodeType <- currentNodeType c
        throwError . D.ParseFailed $ "invalid node type for TopLevelTypeDecl: " <> nodeType

data P4Action = P4Action
  { name        :: Text
  , annotations :: [Annotation]
  , parameters  :: [Parameter]
  , body        :: BlockStatement
  }
  deriving ( Show, Generic )

parseP4Action :: DecompressC r => D.Decoder (Sem r) P4Action
parseP4Action = D.withCursor . tryParseVal $ \c -> do
  o           <- D.down c
  name        <- D.fromKey "name" D.text o
  annotations <- D.fromKey "annotations" parseAnnotations o
  parameters  <- D.fromKey "parameters"
    (parseNestedObject "parameters"
     (parseVector parseParameter)) o
  body        <- D.fromKey "body" parseBlockStatement o
  pure $ P4Action name annotations parameters body

data Declaration
  = P4Action'Declaration P4Action
  | P4Table'Declaration P4Table
  | DeclarationInstance'Declaration DeclarationInstance
  deriving ( Show, Generic )

declarationDecoder :: DecompressC r => D.Decoder (Sem r) Declaration
declarationDecoder = D.withCursor $ \c -> do
  nodeType <- currentNodeType c

  case nodeType of
    "P4Action"             -> (_Typed @P4Action #)            <$> tryDecoder parseP4Action c
    "P4Table"              -> (_Typed @P4Table #)             <$> tryDecoder parseP4Table c
    "Declaration_Instance" -> (_Typed @DeclarationInstance #) <$> tryDecoder parseDeclarationInstance c
    _ -> throwError . D.ParseFailed $ "invalid node type for Declaration: " <> nodeType

data ParserState = ParserState
  { annotations :: [Annotation]
  , components  :: [StatOrDecl]
  }
  deriving ( Show, Generic )

parseParserState :: DecompressC r => D.Decoder (Sem r) ParserState
parseParserState = D.withCursor . tryParseVal $ \c -> do
  o           <- D.down c
  annotations <- D.fromKey "annotations" parseAnnotations o
  components  <- D.fromKey "components" (parseVector statOrDeclDecoder) o
  pure $ ParserState annotations components

data P4Parser = P4Parser
  { name              :: Text
  , type_             :: P4Type
  , constructorParams :: [Parameter]
  , parserLocals      :: [Declaration]
  , states            :: [ParserState]
  }
  deriving ( Show, Generic )

parseP4Parser :: DecompressC r => D.Decoder (Sem r) P4Parser
parseP4Parser = D.withCursor . tryParseVal $ \c -> do
  o                 <- D.down c
  name              <- D.fromKey "name" D.text o
  type_             <- D.fromKey "type" p4TypeDecoder o
  constructorParams <- D.fromKey "constructorParams"
    (parseNestedObject "parameters"
     (parseVector parseParameter)) o
  parserLocals      <- D.fromKey "parserLocals" (parseVector declarationDecoder) o
  states            <- D.fromKey "states" (parseVector parseParserState) o
  pure $ P4Parser name type_ constructorParams parserLocals states

newtype Attribute = Attribute Json
  deriving ( Show, Generic )

newtype DeclarationMatchKind = DeclarationMatchKind
  { members :: [DeclarationID]
  }
  deriving ( Show, Generic )

parseDeclarationMatchKind :: DecompressC r => D.Decoder (Sem r) DeclarationMatchKind
parseDeclarationMatchKind = D.withCursor . tryParseVal $ \c -> do
  o       <- D.down c
  members <- D.fromKey "members" (parseVector parseDeclarationID) o
  pure $ DeclarationMatchKind members

data P4Control = P4Control
  { name              :: Text
  , type_             :: P4Type
  , constructorParams :: [Parameter]
  , controlLocals     :: [Declaration]
  , body              :: BlockStatement
  }
  deriving ( Show, Generic )

parseP4Control :: DecompressC r => D.Decoder (Sem r) P4Control
parseP4Control = D.withCursor . tryParseVal $ \c -> do
  o                 <- D.down c
  name              <- D.fromKey "name" D.text o
  type_             <- D.fromKey "type" p4TypeDecoder o
  constructorParams <- D.fromKey "constructorParams"
    (parseNestedObject "parameters"
     (parseVector parseParameter)) o
  controlLocals      <- D.fromKey "controlLocals" (parseVector declarationDecoder) o
  body              <- D.fromKey "body" parseBlockStatement o
  pure $ P4Control name type_ constructorParams controlLocals body

data P4Table = P4Table
  { name        :: Text
  , annotations :: [Annotation]
  , properties  :: [Property]
  }
  deriving ( Show, Generic )

parseP4Table :: DecompressC r => D.Decoder (Sem r) P4Table
parseP4Table = D.withCursor . tryParseVal $ \c -> do
  o           <- D.down c
  name        <- D.fromKey "name" D.text o
  annotations <- D.fromKey "annotations" parseAnnotations o
  properties  <- D.fromKey "properties"
    (parseNestedObject "properties"
     (parseVector parseProperty)) o
  pure $ P4Table name annotations properties

data PropertyValue
  = PropertyValue'Key Key
  | PropertyValue'ActionList ActionList
  | PropertyValue'ExpressionValue ExpressionValue
  deriving ( Show, Generic )

propertyValueDecoder :: DecompressC r => D.Decoder (Sem r) PropertyValue
propertyValueDecoder = D.withCursor $ \c -> do
  nodeType <- currentNodeType c

  case nodeType of
    "Key"             -> (_Typed @Key #)             <$> tryDecoder parseKey c
    "ActionList"      -> (_Typed @ActionList #)      <$> tryDecoder parseActionList c
    "ExpressionValue" -> (_Typed @ExpressionValue #) <$> tryDecoder parseExpressionValue c
    _ -> throwError . D.ParseFailed $ "invalid node type for PropertyValue: " <> nodeType

data Property = Property
  { name        :: Text
  , annotations :: [Annotation]
  , value       :: PropertyValue
  , isConstant  :: Bool
  }
  deriving ( Show, Generic )

parseProperty :: DecompressC r => D.Decoder (Sem r) Property
parseProperty = D.withCursor . tryParseVal $ \c -> do
  o           <- D.down c
  name        <- D.fromKey "name" D.text o
  annotations <- D.fromKey "annotations" parseAnnotations o
  value       <- D.fromKey "value" propertyValueDecoder o
  isConstant  <- D.fromKey "isConstant" D.bool o
  pure $ Property name annotations value isConstant

newtype Key = Key
  { keyElements :: [KeyElement]
  }
  deriving ( Show, Generic )

parseKey :: DecompressC r => D.Decoder (Sem r) Key
parseKey = D.withCursor . tryParseVal $ \c -> do
  o        <- D.down c
  elems   <- D.fromKey "keyElements" (parseVector parseKeyElement) o
  pure $ Key elems

data KeyElement = KeyElement
  { annotations :: [Annotation]
  , expression  :: Expression
  , matchType   :: Expression
  }
  deriving ( Show, Generic )

parseKeyElement :: DecompressC r => D.Decoder (Sem r) KeyElement
parseKeyElement = D.withCursor . tryParseVal $ \c -> do
  o           <- D.down c
  annotations <- D.fromKey "annotations" parseAnnotations o
  expression  <- D.fromKey "expression" expressionDecoder o
  matchType   <- D.fromKey "matchType" expressionDecoder o
  pure $ KeyElement annotations expression matchType

newtype ExpressionValue = ExpressionValue
  { value :: Expression
  }
  deriving ( Show, Generic )

parseExpressionValue :: DecompressC r => D.Decoder (Sem r) ExpressionValue
parseExpressionValue = D.withCursor . tryParseVal $ \c -> do
  o     <- D.down c
  value <- D.fromKey "expression" expressionDecoder o
  pure $ ExpressionValue value

data DeclarationInstance = DeclarationInstance
  { name        :: Text
  , annotations :: [Annotation]
  , type_       :: P4Type
  , arguments   :: [Argument]
  }
  deriving ( Show, Generic )

parseDeclarationInstance :: DecompressC r => D.Decoder (Sem r) DeclarationInstance
parseDeclarationInstance = D.withCursor . tryParseVal $ \c -> do
  o           <- D.down c
  name        <- D.fromKey "name" D.text o
  annotations <- D.fromKey "annotations" parseAnnotations o
  type_       <- D.fromKey "type" p4TypeDecoder o
  arguments   <- D.fromKey "arguments" (parseVector parseArgument) o
  pure $ DeclarationInstance name annotations type_ arguments
