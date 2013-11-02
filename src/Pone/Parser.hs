module Pone.Parser (parsePone) where

import Control.Applicative((<*))
import Text.Parsec
import Text.Parsec.String
import Text.Parsec.Expr
import Text.Parsec.Token
import Text.Parsec.Language

import Pone.Ast

languageDef = emptyDef{ commentStart = "<"
                      , commentEnd = ">"
                      , identStart = letter
                      , identLetter = alphaNum
                      , opStart = oneOf "+*"
                      , opLetter = oneOf "+*"
                      , reservedOpNames = ["+", "*"]
                      , reservedNames = ["define", "as", "in"]
                      }
    
TokenParser{ parens = m_parens
           , integer = m_number
           , identifier = m_identifier
           , reservedOp = m_reservedOp
           , reserved = m_reserved
           , whiteSpace = m_whiteSpace } = makeTokenParser languageDef
        
opTable = [ [Infix (m_reservedOp "+" >> return (Binop Plus)) AssocLeft]
          , [Infix (m_reservedOp "*" >> return (Binop Times)) AssocLeft]
          ]
        
exprParser :: Parser Expr
exprParser = buildExpressionParser opTable term <?> "expression"
    
term = m_parens exprParser
       <|> fmap Value m_number
       <|> try(do { name <- m_identifier
                  ; args <- argParser
                  ; return $ ProcedureEval name args
                  })
       <|> fmap IdentifierEval m_identifier
       <|> try(do { m_reserved "define"
                  ; name <- m_identifier
                  ; params <- paramParser
                  ; m_reserved "as"
                  ; value <- exprParser
                  ; m_reserved "in"
                  ; expr <- exprParser
                  ; return $ ProcedureBind name params value expr
                  })
       <|> do { m_reserved "define"
              ; name <- m_identifier
              ; m_reserved "as"
              ; value <- exprParser
              ; m_reserved "in"
              ; expr <- exprParser
              ; return $ IdentifierBind name value expr
              }
       

spaceSep1 p = sepBy1 p m_whiteSpace
       
paramParser :: Parser [String]
paramParser = spaceSep1 m_identifier
     
argParser :: Parser [Expr]
argParser = spaceSep1 exprParser
     
mainParser :: Parser Expr
mainParser = m_whiteSpace >> exprParser <* eof

parsePone :: String => Either ParseError Expr
parsePone src = parse mainParser "" src


