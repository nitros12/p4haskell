-- |
module P4Haskell.Compile.Codegen.Typegen
  ( generateP4Type,
    generateP4TypePure,
    resolveType,
    simplifyType,
    resolveP4Type,
  )
where

import qualified Control.Monad.Writer.Strict as SW
import Data.Text.Lens (unpacked)
import qualified Language.C99.Simple as C
import P4Haskell.Compile.Codegen.Extern
import P4Haskell.Compile.Declared
import P4Haskell.Compile.Eff
import P4Haskell.Compile.Fetch
import P4Haskell.Compile.Query
import qualified P4Haskell.Types.AST as AST
import Polysemy
import Polysemy.State
import Relude (error)
import Relude.Unsafe (fromJust)
import qualified Rock

generateP4Type :: CompC r => AST.P4Type -> Sem r (C.TypeSpec, C.TypeSpec)
generateP4Type t = do
  (ty, rawTy, deps) <- embedTask $ generateP4TypePure t
  forM_ deps (modify . (<>) . uncurry declareType)
  pure (ty, rawTy)

resolveType :: CompC r => C.TypeSpec -> Sem r C.TypeSpec
resolveType t@(C.TypedefName name) = fetchTyByName name <&> fromMaybe t
resolveType t@(C.Struct name) = fetchTyByName name <&> fromMaybe t
resolveType ty = pure ty

fetchTyByName :: CompC r => C.Ident -> Sem r (Maybe C.TypeSpec)
fetchTyByName name = do
  ty <- gets $ getType (toText name)
  case ty of
    Just ty' -> pure (Just ty')
    Nothing -> do
      p4ty <- fetch $ FetchType (toText name)
      mapM ((snd <$>) . generateP4Type) p4ty

simplifyType :: CompC r => C.TypeSpec -> Sem r C.TypeSpec
simplifyType t@(C.StructDecln (Just name) _) = do
  modify . (<>) $ declareType (toText name) t
  pure $ C.Struct name
simplifyType t = pure t

resolveP4Type :: CompC r => AST.P4Type -> Sem r AST.P4Type
resolveP4Type (AST.TypeName'P4Type p) = fromJust <$> fetch (FetchType $ p ^. #path . #name)
resolveP4Type t = pure t

generateP4TypePure :: Rock.MonadFetch Query m => AST.P4Type -> m (C.TypeSpec, C.TypeSpec, [(Text, C.TypeSpec)])
generateP4TypePure (AST.TypeStruct'P4Type s) = generateP4StructPure s
generateP4TypePure (AST.TypeHeader'P4Type s) = generateP4HeaderPure s
generateP4TypePure (AST.TypeEnum'P4Type s) = generateP4EnumPure s
generateP4TypePure (AST.TypeError'P4Type s) = generateP4ErrorPure s
generateP4TypePure (AST.TypeVoid'P4Type s) = generateP4VoidPure s
generateP4TypePure (AST.TypeBits'P4Type s) = generateP4BitsPure s
generateP4TypePure (AST.TypeName'P4Type s) = generateP4TypeNamePure s
generateP4TypePure (AST.TypeBoolean'P4Type s) = generateP4BoolPure s
generateP4TypePure (AST.TypeString'P4Type s) = generateP4StringPure s
generateP4TypePure (AST.TypeTypedef'P4Type s) = generateP4TypeDefPure s
generateP4TypePure (AST.TypeExtern'P4Type s) = generateP4ExternPure s
-- generateP4TypePure (AST.TypeParser'P4Type s) = generateP4ParserPure s
-- generateP4TypePure (AST.TypeControl'P4Type s) = generateP4ControlPure s
generateP4TypePure t = error $ "The type: " <> show t <> " shouldn't exist at this point"

dupFst :: (a, b) -> (a, a, b)
dupFst (a, b) = (a, a, b)

generateP4ExternPure :: Rock.MonadFetch Query m => AST.TypeExtern -> m (C.TypeSpec, C.TypeSpec, [(Text, C.TypeSpec)])
generateP4ExternPure e =
  pure
    let ty = getExternType $ e ^. #name
     in (extractInfo ty, ty, [])
  where
    extractInfo (C.StructDecln (Just name) _) = C.Struct name
    extractInfo x = x

generateP4VoidPure :: Rock.MonadFetch Query m => AST.TypeVoid -> m (C.TypeSpec, C.TypeSpec, [(Text, C.TypeSpec)])
generateP4VoidPure _ = pure $ dupFst (C.Void, [])

generateP4BitsPure :: Rock.MonadFetch Query m => AST.TypeBits -> m (C.TypeSpec, C.TypeSpec, [(Text, C.TypeSpec)])
generateP4BitsPure (AST.TypeBits size isSigned) =
  case find (size <=) [8, 16, 32, 64] of
    Just size' ->
      let signChar = if isSigned then "" else "u"
       in pure $ dupFst (C.TypedefName $ signChar <> "int" <> show size' <> "_t", [])
    Nothing -> error $ "unsupported bit width: " <> show size

generateP4TypeNamePure :: Rock.MonadFetch Query m => AST.TypeName -> m (C.TypeSpec, C.TypeSpec, [(Text, C.TypeSpec)])
generateP4TypeNamePure (AST.TypeName p) = do
  type_ <- fromJust <$> Rock.fetch (FetchType $ p ^. #name)
  Rock.fetch $ GenerateP4Type type_

generateP4BoolPure :: Rock.MonadFetch Query m => AST.TypeBoolean -> m (C.TypeSpec, C.TypeSpec, [(Text, C.TypeSpec)])
generateP4BoolPure AST.TypeBoolean = pure $ dupFst (C.Bool, [])

stringStruct :: C.TypeSpec
stringStruct =
  C.StructDecln
    (Just "p4string")
    ( fromList
        [ C.FieldDecln (C.Const . C.Ptr . C.Const $ C.TypeSpec C.Char) "str",
          C.FieldDecln (C.Const . C.TypeSpec $ C.TypedefName "size_t") "len"
        ]
    )

generateP4StringPure :: Rock.MonadFetch Query m => AST.TypeString -> m (C.TypeSpec, C.TypeSpec, [(Text, C.TypeSpec)])
generateP4StringPure AST.TypeString = pure (C.Struct "p4string", stringStruct, [])

generateP4TypeDefPure :: Rock.MonadFetch Query m => AST.TypeTypedef -> m (C.TypeSpec, C.TypeSpec, [(Text, C.TypeSpec)])
generateP4TypeDefPure td = Rock.fetch $ GenerateP4Type (td ^. #type_)

-- NOTE: we silently ignore the name of the typedef here and just return the true name of the type

-- generateP4ParserPure :: (Rock.MonadFetch Query m, MonadIO m) => AST.TypeParser -> m (C.TypeSpec, C.TypeSpec, [(Text, C.TypeSpec)])
-- generateP4ParserPure p = do
--   when (null $ p ^. #typeParameters) $
--     print $ "Parser: " <> (p ^. #name) <> " has type parameters that are being ignored"

--   (params, deps) <-
--     SW.runWriterT $
--       forM
--         (p ^. #applyParams . #vec)
--         ( \param -> do
--             (ty, deps) <- Rock.fetch $ GenerateP4Type (param ^. #type_)
--             let ty' = if param ^. #direction . #out then C.Ptr ty else ty
--             SW.tell deps
--             pure $ C.Param ty' (toString $ param ^. #name)
--         )
--   let ident = toString $ p ^. #name
--   let fn = C.FunDecln Nothing (C.TypeSpec C.Void) ident params
--   pure (C.TypeSpec . C.TypedefName $ ident, (p ^. #name, fn) : deps)

-- generateP4ControlPure :: (Rock.MonadFetch Query m, MonadIO m) => AST.TypeControl -> m (C.TypeSpec, C.TypeSpec, [(Text, C.TypeSpec)])
-- generateP4ControlPure p = do
--   when (null $ p ^. #typeParameters) $
--     print $ "Control: " <> (p ^. #name) <> " has type parameters that are being ignored"

--   (params, deps) <-
--     SW.runWriterT $
--       forM
--         (p ^. #applyParams . #vec)
--         ( \param -> do
--             (ty, deps) <- Rock.fetch $ GenerateP4Type (param ^. #type_)
--             let ty' = if param ^. #direction . #out then C.Ptr ty else ty
--             SW.tell deps
--             pure $ C.Param ty' (toString $ param ^. #name)
--         )
--   let ident = toString $ p ^. #name
--   let fn = C.FunDecln Nothing (C.TypeSpec C.Void) ident params
--   pure (C.TypeSpec . C.TypedefName $ ident, (p ^. #name, fn) : deps)

generateP4StructPure :: Rock.MonadFetch Query m => AST.TypeStruct -> m (C.TypeSpec, C.TypeSpec, [(Text, C.TypeSpec)])
generateP4StructPure s = do
  let fields = s ^. #fields . #vec
  (fields', deps) <-
    SW.runWriterT $
      forM
        fields
        ( \f -> do
            (ty, _, deps) <- Rock.fetch $ GenerateP4Type (f ^. #type_)
            SW.tell deps
            pure $ C.FieldDecln (C.TypeSpec ty) (toString $ f ^. #name)
        )
  let ident = toString $ s ^. #name
  let struct = C.StructDecln (Just ident) (fromList fields')
  let deps' = ((s ^. #name, struct) : deps)
  pure (C.Struct ident, struct, deps')

generateP4HeaderPure :: Rock.MonadFetch Query m => AST.TypeHeader -> m (C.TypeSpec, C.TypeSpec, [(Text, C.TypeSpec)])
generateP4HeaderPure h = do
  let fields = h ^. #fields . #vec
  (fields', deps) <-
    SW.runWriterT $
      forM
        fields
        ( \f -> do
            (ty, _, deps) <- Rock.fetch $ GenerateP4Type (f ^. #type_)
            SW.tell deps
            pure $ C.FieldDecln (C.TypeSpec ty) (toString $ f ^. #name)
        )
  let ident = toString $ h ^. #name
  let struct = C.StructDecln (Just ident) (fromList fields')
  let deps' = ((h ^. #name, struct) : deps)
  pure (C.Struct ident, struct, deps')

generateP4EnumPure :: Rock.MonadFetch Query m => AST.TypeEnum -> m (C.TypeSpec, C.TypeSpec, [(Text, C.TypeSpec)])
generateP4EnumPure e =
  let values = e ^.. #members . #vec . traverse . #name . unpacked
      ident = toString $ e ^. #name
      enum' = C.EnumDecln (Just ident) (fromList values)
   in pure (C.Enum ident, enum', [(e ^. #name, enum')])

generateP4ErrorPure :: Rock.MonadFetch Query m => AST.TypeError -> m (C.TypeSpec, C.TypeSpec, [(Text, C.TypeSpec)])
generateP4ErrorPure e =
  let values = e ^.. #members . #vec . traverse . #name . unpacked
      ident = toString $ e ^. #name
      enum' = C.EnumDecln (Just ident) (fromList values)
   in pure (C.Enum ident, enum', [(e ^. #name, enum')])
