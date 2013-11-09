{-# LANGUAGE TemplateHaskell #-}
module Pone.Interpreter (poneEval) where
import qualified Data.Map as Map

import Debug.Trace
import Data.Monoid
import Data.List (find)
import Control.Lens
import Control.Exception
import Control.Monad

--import System.IO.Unsafe

import Pone.Ast
import Pone.Parser   
import Pone.Utils 
      
type RuntimeError = String
      
--data ProcedureDef = ProcedureDef String [String] Expr deriving Show
data TypeDef = TypeDef String [String] deriving Show
data Environment = Environment { _names :: Map.Map String Expr
                               , _types :: Map.Map String TypeDef
                               } deriving Show

makeBuiltins :: Map.Map String Expr
makeBuiltins = Map.insert "toInt" (Value $ Builtin "toInt" toInt) Map.empty 

toInt :: Expr -> Expr
toInt e = case e of 
    Value (PoneFloat f) -> Value $ PoneInteger $ truncate f
    _ -> undefined
makeLambda :: String -> Expr -> Expr
makeLambda name expr = (Value $ Lam $ Lambda name expr)


makeEnv = Environment makeBuiltins Map.empty



makeLenses ''Environment 

pushName :: Environment -> String -> Expr -> Environment
pushName env name value = names %~ Map.insert name value $ env

lookupName :: Environment -> String -> Maybe Expr
lookupName env name = Map.lookup name (env ^. names)

pushType :: Environment -> String -> TypeDef -> Environment
pushType env name type' = types %~ Map.insert name type' $ env

lookupType :: Environment -> String -> Maybe TypeDef
lookupType env name = Map.lookup name (env ^. types)
    
bind :: Environment -> GlobalDef -> Either RuntimeError Environment
bind env def = case def of
    --GlobalProcedureBind (ProcedureBind name parameters body) ->
    --    return $ pushProc env name $ ProcedureDef name parameters body
    GlobalIdentifierBind (IdentifierBind name value) -> do
        return $ pushName env name value
    GlobalTypeBind (TypeBind name ctors) -> return env

envMultiBind :: Environment -> [(String, Expr)] -> Environment
envMultiBind env [] = env
envMultiBind env ((p, v):xs) = envMultiBind (pushName env p v) xs

extractExpr :: Pattern -> Expr
extractExpr (Pattern _ expr) = expr
    
extractLit :: Pattern -> Var
extractLit (Pattern lit _) = lit
    
findLit :: Var -> (Pattern -> Bool)
findLit l pattern = let lit = extractLit pattern in lit == l
    
matchPattern :: Var -> [Pattern] -> Maybe Expr
matchPattern lit patterns = fmap extractExpr maybeFound
    where maybeFound :: Maybe Pattern
          maybeFound = (find (findLit lit) patterns)
          
eval :: Environment -> Expr -> Either RuntimeError Var
eval env expr = case expr of

    PatternMatch expr patterns -> do
        value :: Var <- eval env expr
        case matchPattern value patterns of
            Just match -> do 
                matchValue <- eval env match
                return matchValue
            Nothing -> Left ("failed to match pattern " ++ (show expr))
            

    Value literal -> case literal of
        Identifier ident -> do 
            case lookupName env ident of 
                Just match -> eval env match
                Nothing -> Left ("unbound name " ++ (show ident))--look up builtins
            
        _ -> return literal

    Apply l r -> do
        rhs :: Var <- eval env r
        lhs :: Var <- eval env l
        case lhs of 
            Lam (Lambda name inner) ->
                let newEnv = pushName env name (Value rhs) in 
                    eval newEnv inner
            Builtin name func -> eval env $ func (Value rhs)
            _ -> Left $ "type error: cannot apply " ++ (show l) ++ " == " ++ (show lhs) ++ " as it is not a function"
    LocalIdentifierBind (IdentifierBind name v) e -> do
        value <- eval env v
        let newEnv = (pushName env name (Value value)) in 
            eval newEnv e
    --make sure no repeat args
    --LocalProcedureBind (ProcedureBind name args value) expr ->  
    --    let newEnv = pushProc env name (ProcedureDef name args value) in 
    --    eval newEnv expr
        
    --IdentifierEval s -> case lookupName env s of
    --    Just value -> return value
    --    Nothing -> Left ("Unbound name: " ++ (show s))


    --ProcedureEval name args -> case name of
    --    "add" -> do v1 <- eval env (args !! 0) --fixme, 
    --                v2 <- eval env (args !! 1)
    --                case (v1, v2) of 
    --                    (PoneInteger i, PoneInteger j) -> return $ PoneInteger (i + j)
    --                    _ -> Left ("type error")
    --    "toInt" -> do float <- eval env (args !! 0)
    --                  case float of 
    --                      PoneInteger i -> Left ("type error")
    --                      PoneFloat f -> return $ PoneInteger $ truncate f 
    --                      UserType _ -> Left ("type error")
    --    other -> do
    --        -- [Either String Var] -> Either String [Var]
    --        evaluated :: [Var] <- sequence $ map (eval env) args-- :: [Either String Var]
    --        case lookupProc env other of 
    --            Just (ProcedureDef other params expr) ->
    --                let zipped :: [(String, Var)] = zip params evaluated -- make sure same length
    --                    newEnv :: Environment = envMultiBind env zipped 
    --                in eval newEnv expr
    --            Nothing -> Left $ "Unbound procedure: " ++ (show other) ++ (show expr)



tryAny :: IO a -> IO (Either SomeException a)
tryAny = Control.Exception.try

showException :: Either SomeException a -> Either String a
showException (Left exc) = Left $ ("Interpreter: " ++) $ show exc
showException (Right x) = Right x

poneEval :: PoneProgram -> IO (Either RuntimeError Var)
poneEval (Program globals expr) = 
    let env :: Either RuntimeError Environment = foldM bind makeEnv globals
    in case env of 
        Left err -> return $ Left err
        Right e -> do
            r <- fmap showException $ tryAny $ evaluate $ eval e expr      
            evaluate $ join $ r
    
