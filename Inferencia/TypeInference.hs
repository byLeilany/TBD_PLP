module TypeInference (TypingJudgment, Result(..), inferType, inferNormal, normalize)

where

import Data.List(intersect, union, nub, sort)
import Exp
import Type
import Unification

------------
-- Errors --
------------
data Result a = OK a | Error String


--------------------
-- Type Inference --
--------------------
type TypingJudgment = (Context, AnnotExp, Type)

typeVarsT :: Type -> [Int]
typeVarsT = foldType (:[]) [] [] union

typeVarsE :: Exp Type -> [Int]
typeVarsE = foldExp (const []) [] id id id [] [] (\r1 r2 r3 ->nub(r1++r2++r3)) (const setAdd) union
  where setAdd t r = union (typeVarsT t) r

typeVarsC :: Context -> [Int]
typeVarsC c = nub (concatMap (typeVarsT . evalC c) (domainC c))

typeVars :: TypingJudgment -> [Int]
typeVars (c, e, t) = sort $ union (typeVarsC c) (union (typeVarsE e) (typeVarsT t))

normalization :: [Int] -> [Subst]
normalization ns = foldr (\n rec (y:ys) -> extendS n (TVar  y) emptySubst : (rec ys)) (const []) ns [0..]

normalize :: TypingJudgment -> TypingJudgment
normalize j@(c, e, t) = let ss = normalization $ typeVars j in foldl (\(rc, re, rt) s ->(s <.> rc, s <.> re, s <.> rt)) j ss
  
inferType :: PlainExp -> Result TypingJudgment
inferType e = case infer' e 0 of
    OK (_, tj) -> OK tj
    Error s -> Error s
    
inferNormal :: PlainExp -> Result TypingJudgment
inferNormal e = case infer' e 0 of
    OK (_, tj) -> OK $ normalize tj
    Error s -> Error s


infer' :: PlainExp -> Int -> Result (Int, TypingJudgment)

infer' (SuccExp e)    n =
  case infer' e n of
    err@(Error _) -> err
    OK (n', (c', e', t')) ->
      case mgu [(t', TNat)] of
        UError u1 u2 -> uError u1 u2
        UOK subst -> OK (n', (subst <.> c',
                              subst <.> SuccExp e',
                              TNat))
    

-- COMPLETAR DESDE AQUI

infer' ZeroExp                n = OK(n, (emptyContext, ZeroExp, TNat))
infer' (VarExp x)             n = OK(n+1, (extendC emptyContext x (TVar (n)), VarExp x, (TVar (n))))
infer' (AppExp u v)           n = 
  
  case infer' u n of
    err@(Error _) -> err
    OK(n',(c',e',t')) -> 
      
      case infer' v n' of 
        err@(Error _) -> err
        OK(m,(d,f,r)) ->
          case mgu ([(t', TFun r (TVar m))]++[(evalC c' x, evalC d x) | x <-(intersect (domainC c') (domainC d))]) of 
            UError u1 u2 -> uError u1 u2
            UOK subst -> OK((m+1), (subst <.> (joinC [c', d]), subst <.> (AppExp e' f), subst <.> (TVar m)))


                             
infer' (LamExp x _ e)         n =   
  case infer' e n of 
    err@(Error _) -> err
    OK (n',(c',e',t')) -> 
      if (elem x (domainC c')) then OK (n', (removeC c' x, LamExp x (evalC c' x) e', TFun (evalC c' x) t'))
      else OK (n'+1, (removeC c' x, LamExp x (TVar n') e', TFun (TVar n') t'))


-- OPCIONALES

infer' (PredExp e)            n = 
  case infer' e n of 
  err@(Error _) -> err
  OK(m,(d,f,r)) ->
    case mgu ([(TNat, r)]) of 
      UError u1 u2 -> uError u1 u2
      UOK subst -> OK((m+1), (subst <.> d, subst <.> (PredExp f), TNat))



infer' (IsZeroExp e)          n = 
  case infer' e n of 
  err@(Error _) -> err
  OK(m,(d,f,r)) ->
    case mgu ([(TNat, r)]) of 
      UError u1 u2 -> uError u1 u2
      UOK subst -> OK((m+1), (subst <.> d, subst <.> (IsZeroExp f), TBool))
 

infer' TrueExp                n = OK(n, (emptyContext, TrueExp, TBool))

infer' FalseExp               n = OK(n, (emptyContext, FalseExp, TBool))

infer' (IfExp u v w)          n = undefined

--------------------------------
-- YAPA: Error de unificacion --
--------------------------------
uError :: Type -> Type -> Result (Int, a)
uError t1 t2 = Error $ "Cannot unify " ++ show t1 ++ " and " ++ show t2
