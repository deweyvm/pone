﻿{-# LANGUAGE FlexibleInstances #-}
module Pone.Monoid 
( Monoid
, zero
) where 

import Pone.Semigroup
import Pone.Option

{- additional laws
  ∀x ∈ a,  zero <+> x === x <+> zero
-}
class Semigroup a => Monoid a where
    zero :: a
    
instance Monoid Int where
    zero = 0
    
instance Monoid [a] where
    zero = []
    
instance Monoid (a -> a) where
    zero = id
    
instance Monoid a => Monoid (Option a) where
    zero = None