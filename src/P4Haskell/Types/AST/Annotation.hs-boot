-- | P4 Annotations
module P4Haskell.Types.AST.Annotation
    ( Annotation
    , parseAnnotations
    , parseAnnotation
    , AnnotatedToken
    , NamedExpression
    , parseAnnotatedToken
    , parseNamedExpression ) where

import Relude
import           P4Haskell.Types.AST.DecompressJSON

import           Polysemy

import qualified Waargonaut.Decode                  as D

data Annotation

instance Show Annotation

instance Eq Annotation

instance Hashable Annotation

parseAnnotations :: DecompressC r => D.Decoder (Sem r) [Annotation]

parseAnnotation :: DecompressC r => D.Decoder (Sem r) Annotation

type AnnotatedToken = Text

parseAnnotatedToken :: Monad m => D.Decoder m AnnotatedToken

type NamedExpression = Text

parseNamedExpression :: Monad m => D.Decoder m NamedExpression
