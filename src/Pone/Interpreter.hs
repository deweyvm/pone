{-# LANGUAGE TemplateHaskell #-}
module Pone.Interpreter (poneEval) where
import qualified Data.Map as Map

import Debug.Trace
import Control.Lens

import Pone.Ast
import Pone.Parser    
          
data ProcedureDef = ProcedureDef String [String] Expr
data Environment = Environment { _names :: Map.Map String Integer
                               , _procs :: Map.Map String ProcedureDef
                               }     
            
makeEnv = Environment Map.empty Map.empty
            
makeLenses ''Environment 

pushDef :: Environment -> String -> ProcedureDef -> Environment
pushDef env name def = procs %~ Map.insert name def $ env

lookupDef :: Environment -> String -> ProcedureDef
lookupDef env name = (Map.!) (env ^. procs) name --fixme, handle unbound names

pushName :: Environment -> String -> Integer -> Environment
pushName env name value = names %~ Map.insert name value $ env

lookupName :: Environment -> String -> Integer
lookupName env name = (Map.!) (env ^. names) name --fixme, handle unbound names

poneEval :: PoneProgram -> Integer
poneEval (Program globals expr) = 
    let env = foldl (\acc def -> bind acc def) makeEnv globals
    in eval env expr

    
bind :: Environment -> GlobalDef -> Environment
bind env def = case def of
    GlobalProcedureBind (ProcedureBind name parameters body) ->
        pushDef env name (ProcedureDef name parameters body)
    GlobalIdentifierBind (IdentifierBind name value) -> 
        let evaluated = eval env value in
        pushName env name evaluated


envMultiBind :: Environment -> [(String, Integer)] -> Environment
envMultiBind env [] = env
envMultiBind env ((param, value):xs) = envMultiBind (pushName env param value) xs

eval :: Environment -> Expr -> Integer
eval env expr = case expr of
    Value (PoneInteger i) -> i 
    Binop op e1 e2 -> 
        let v1 = eval env e1
            v2 = eval env e2
        in case op of 
            Plus -> v1 + v2
            Times -> v1 * v2
                                 
    LocalIdentifierBind (IdentifierBind name v) e -> 
        let value = eval env v
            newState = pushName env name value
        in eval newState e
        
    LocalProcedureBind (ProcedureBind name args value) expr ->  --make sure no repeat args
        let newEnv = pushDef env name (ProcedureDef name args value) in 
        eval newEnv expr
        
    IdentifierEval s -> lookupName env s
    
    ProcedureEval name args -> 
        let evaluated :: [Integer] = map (eval env) args
            procc = lookupDef env name
        in case procc of 
            ProcedureDef name params expr ->
                let zipped :: [(String, Integer)] = zip params evaluated -- make sure same length
                    newEnv :: Environment = envMultiBind env zipped 
                in eval newEnv expr
                
