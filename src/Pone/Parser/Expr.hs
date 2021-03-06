
module Pone.Parser.Expr (parsePone) where

import Control.Applicative((<*), (*>), (<*>), (<$>))
import Control.Monad
import Data.Functor.Identity
import Text.Parsec
import Text.Parsec.String
import Text.Parsec.Language
import Debug.Trace

import Pone.Ast
import Pone.Utils ((.:))
import Pone.Parser.Type (parseType, parseTypeCtor, parseTypeName)
import Pone.Parser.Common
import Pone.Pretty

spaceSep1 :: Parser t -> Parser [t]
spaceSep1 p = sepBy1 p whiteSpace

comSep1 :: Parser t -> Parser [t]
comSep1 p = sepBy1 p comma

arrowSep1 :: Parser t -> Parser [t]
arrowSep1 p = sepBy1 p (reserved "->")

tryParseMany :: (Parser t -> Parser [t]) -> Parser t -> Parser [t]
tryParseMany sep parser = try (sep parser) <|> return []

tryParseManySpace :: Parser a -> Parser [a]
tryParseManySpace parser = tryParseMany spaceSep1 parser

tryParseManyComma :: Parser a -> Parser [a]
tryParseManyComma parser = tryParseMany comSep1 parser

tryParseMaybe :: Parser a -> Parser (Maybe a)
tryParseMaybe parser = (Just <$> try (parser)) <|> return Nothing

getLoc :: Parser Location
getLoc = do
    pos <- getPosition
    return $ Location (sourceLine pos) (sourceColumn pos) (sourceName pos)

parseMain :: Parser (PoneProgram (Type Kind))
parseMain = Program <$> (whiteSpace *> (many parseGlobalDef)) <*> parseExpr

parseGlobalDef :: Parser (GlobalDef (Type Kind))
parseGlobalDef =
      DefSource <$> getLoc <*> choice [ parseTypeDef
                                      , parseInterfaceDef
                                      , parseGlobalFunction
                                      , parseImplementationDef
                                      ]

parseTypeDef :: Parser (GlobalDef t)
parseTypeDef =
    TypeDef <$> (reserved "type" *> parseTypeCtor)
            <*> (tryParseManySpace identifier)
            <*> (reserved "is" *> parseTypeDefList <* reserved "end")

parseTypeDefList :: Parser [CompoundType]
parseTypeDefList =
    tryParseManySpace (reserved "|" *> parseCompoundType)

parseCompoundType :: Parser CompoundType
parseCompoundType =
    CompoundType <$> parseTypeCtor
                 <*> tryParseManySpace (parseTypeCtor <|> identifier)


parseInterfaceDef :: Parser (GlobalDef (Type Kind)) =
    InterfaceDef <$> (reserved "interface" *> parseCompoundType)
                 <*> (try (reserved "extends" *> tryParseManyComma parseCompoundType) <|> return [])
                 <*> (reserved "is" *> tryParseManySpace (parseDefinition parseDefinitionBodyEnd) <* reserved "end")

parseDefinitionBodyEnd :: Parser (Maybe (Expr (Type Kind)))
parseDefinitionBodyEnd = (reserved "as" *> (Just <$> parseExpr <* reserved "end"))
                  <|> (reserved "abstract" *> return Nothing)

parseDefinitionBody :: Parser (Maybe (Expr (Type Kind)))
parseDefinitionBody = (reserved "as" *> (Just <$> parseExpr))
                   <|> (reserved "abstract" *> return Nothing)

parseDefinition :: Parser (Maybe (Expr (Type Kind))) -> Parser (Definition (Type Kind))
parseDefinition exprP =
    Definition <$> (reserved "define" *> identifier)
               <*> tryParseManySpace identifier
               <*> (reserved ":" *> parseType)
               <*> (try (reserved "where" *> parens (tryParseManyComma parseConstraint)) <|> return [])
               <*> exprP


parseLocalDefinition :: Parser (Expr (Type Kind))
parseLocalDefinition =
    LocalDefine <$> (parseDefinition parseDefinitionBody) <*> (reserved "in" *> parseExpr)

parseConstraint :: Parser (Constraint (Type Kind))
parseConstraint =
    Constraint <$> identifier
               <*> (reserved "<" *> parseType)


parseImplementationDef :: Parser (GlobalDef (Type Kind))
parseImplementationDef =
    ImplementationDef <$> (reserved "implement" *> parseCompoundType)
                      <*> (reserved "for" *> parseCompoundType)
                      <*> (try (reserved "where" *> parens (tryParseManyComma parseConstraint)) <|> return [])
                      <*> (reserved "as" *> tryParseManySpace ((parseDefinition parseDefinitionBody) <* reserved "end") <* reserved "end")

parseGlobalFunction :: Parser (GlobalDef (Type Kind))
parseGlobalFunction =
    GlobalFunction <$> ((parseDefinition parseDefinitionBody) <* reserved "end")

parseExprNoApply :: Parser (Expr (Type Kind))
parseExprNoApply =
    Source <$> getLoc <*> choice [ parens parseExpr
                                 , parseLiteral
                                 , brackets parseLambda
                                 , parseIdentifier
                                 ]

parseExpr :: Parser (Expr (Type Kind))
parseExpr = parsePatternMatch
        <|> parseLocalDefinition
        <|> try(parseApply)
        <|> parseExprNoApply


parsePatternMatch :: Parser (Expr (Type Kind))
parsePatternMatch =
    PatternMatch <$> (reserved "match" *> parseExpr <* reserved "with")
                 <*> ((many parsePatternBranch) <* reserved "end")


parsePatternBranch :: Parser (PatternBranch (Type Kind))
parsePatternBranch =
    Branch <$> (reserved "|" *> parsePattern)
           <*> (reserved "->" *> parseExpr)


parsePattern :: Parser Pattern
parsePattern = try (LiteralPattern <$> parseValue)
           <|> TypePattern <$> parseCompoundType
           <|> IdentifierPattern <$> identifier

parseGenApply :: (t -> t -> t) -> Parser t -> Parser t
parseGenApply f parser =
    ((listToApply f) . ApplyList) <$> do { first <- parser
                                         ; second <- parser
                                         ; rest <- try (many parser) <|> return []
                                         ; return $ (first:second:rest)
                                         }

parseApply :: Parser (Expr (Type Kind))
parseApply = parseGenApply Apply parseExprNoApply

parseLiteral :: Parser (Expr (Type Kind))
parseLiteral = Literal <$> parseValue <*> return UnknownT

parseValue :: Parser Value
parseValue = choice [ try(parseFloat)
                    , parseInteger
                    , parseString
                    ]

parseInteger :: Parser Value
parseInteger = PoneInteger <$> integer

parseFloat :: Parser Value
parseFloat = PoneFloat <$> float

parseString :: Parser Value
parseString = PoneString <$> stringLiteral

parseIdentifier :: Parser (Expr (Type Kind))
parseIdentifier = Identifier <$> (identifier <|> parseTypeCtor) <*> return UnknownT

parseLambda :: Parser (Expr (Type Kind))
parseLambda = Lambda <$> (reserved "λ" *> identifier)
                     <*> (reserved "." *> parseExpr)

convertError :: Either ParseError (PoneProgram t) -> Either String (PoneProgram t)
convertError (Left err) = Left $ show err
convertError (Right prog) = Right prog

printAst :: Pretty t => Either a (PoneProgram t) -> Either a (PoneProgram t)
printAst arg = case arg of
    Left err -> arg
    Right ast -> trace ((pretty $ stripSource ast) ++ "\n") arg

parsePone :: String -> String -> Either String (PoneProgram (Type Kind))
parsePone filename src = convertError $ printAst  $ parse parseMain filename src
