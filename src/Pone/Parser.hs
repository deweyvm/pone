module Pone.Parser (parsePone) where

import Control.Applicative((<*))
import Text.Parsec
import Text.Parsec.String
import Text.Parsec.Expr
import Text.Parsec.Token
import Text.Parsec.Language
import Debug.Trace

import Pone.Ast

languageDef = emptyDef{ commentStart = "<"
                      , commentEnd = ">"
                      , commentLine = "comment"
                      , identStart = lower
                      , identLetter = alphaNum
                      , reservedNames = ["define", "as", "in", ";", "|"]
                      , caseSensitive = True
                      }
    
    
    
TokenParser{ parens = m_parens
           , integer = m_number
           , identifier = m_identifier
           , reservedOp = m_reservedOp
           , reserved = m_reserved
           , whiteSpace = m_whiteSpace } = makeTokenParser languageDef

         
exprParser :: Parser Expr
exprParser = m_parens exprParser
        <|> do { number <- m_number
               ; return $ Value $ PoneInteger number
               }
        <|> do { name <- m_identifier
               ; args <- try (spaceSep1 exprParser) <|> return []
               ; return $ case args of 
                   [] -> IdentifierEval name
                   xs -> ProcedureEval name args
               }
        <|> do { m_reserved "define"
               ; name <- m_identifier
               ; params <- try (many m_identifier) <|> return []
               ; m_reserved "as"
               ; value <- exprParser
               ; m_reserved "in"
               ; expr <- exprParser
               ; return $ case params of
                   [] -> LocalIdentifierBind (IdentifierBind name value) expr
                   xs -> LocalProcedureBind (ProcedureBind name xs value) expr
               }
        
       
globalDefParser :: Parser GlobalDef
globalDefParser = try(do { m_reserved "define"
                         ; name <- m_identifier
                         ; params <- try (many m_identifier) <|> return []
                         ; m_reserved "as"
                         ; value <- exprParser 
                         ; m_reserved ";"
                         ; return $ case params of
                             [] -> GlobalIdentifierBind (IdentifierBind name value)
                             xs -> GlobalProcedureBind (ProcedureBind name xs value)
                         })
                  <|> do { m_reserved "type"
                         ; name <- typeIdentifier
                         ; m_reserved "is"
                         ; names <- rodSep1 typeIdentifier
                         ; m_reserved ";"
                         ; return $ GlobalTypeBind (TypeBind name names)
                         }

typeIdentifier :: Parser String
typeIdentifier = try $ do { x <- upper
                          ; xs <- many alphaNum
                          ; _ <- m_whiteSpace
                          ; return (x:xs)
                          }


rodSep1 p = sepBy1 p (m_reserved "|")
    
spaceSep1 p = sepBy1 p m_whiteSpace

     
programParser :: Parser PoneProgram
programParser = do { globalDefs <- many globalDefParser
                   ; expr <- exprParser
                   ; return $ Program globalDefs expr
                   }

mainParser :: Parser PoneProgram
mainParser = m_whiteSpace >> programParser <* eof

convertError :: Either ParseError PoneProgram -> Either String PoneProgram
convertError (Left err) = Left $ show err
convertError (Right prog) = Right prog

printAst :: Either a PoneProgram -> Either a PoneProgram
printAst arg = case arg of 
    Left err -> arg
    Right ast -> trace (show ast) arg

parsePone :: String -> Either String PoneProgram
parsePone src = convertError $ {-printAst $-} parse mainParser "" src


