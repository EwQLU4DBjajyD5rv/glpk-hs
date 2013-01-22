{-# LANGUAGE TupleSections, RecordWildCards, DeriveFunctor #-}
module Data.LinearProgram.Spec (Constraint(..), VarTypes, ObjectiveFunc, VarBounds, LP(..),
	mapVars, mapVals) where

import Control.Applicative ((<$>))
import Control.Monad

import Data.Char (isSpace)
import Data.Monoid
import Data.Map hiding (map)

import Text.ParserCombinators.ReadP

import Data.LinearProgram.LinFunc
import Data.LinearProgram.Types

data Constraint v c = Constr (Maybe String)
			(LinFunc v c)
			(Bounds c) deriving (Functor)
type VarTypes v = Map v VarKind
type ObjectiveFunc = LinFunc
type VarBounds v c = Map v (Bounds c)

data LP v c = LP {direction :: Direction, objective :: ObjectiveFunc v c, constraints :: [Constraint v c],
			varBounds :: VarBounds v c, varTypes :: VarTypes v} deriving (Read, Show, Functor)

showBds :: Show c => String -> Bounds c -> String
showBds expr bds = case bds of
	Free	-> expr ++ " free"
	Equ x	-> expr ++ " = " ++ show x
	LBound x -> expr ++ " >= " ++ show x
	UBound x -> expr ++ " <= " ++ show x
	Bound l u -> show l ++ " <= " ++ expr ++ " <= " ++ show u

showFunc :: (Show v, Num c, Ord c) => LinFunc v c -> String
showFunc func = case assocs func of
	[]	-> "0"
	((v,c):vcs) ->
		show c ++ " " ++ map replaceSpace (show v) ++ 
			concatMap showTerm vcs
	where	showTerm (v, c) = case compare c 0 of
			EQ	-> ""
			GT	-> " + " ++ show c ++ " " ++ show v
			LT	-> " - " ++ show (negate c) ++ " " ++ show v
		
replaceSpace :: Char -> Char
replaceSpace c
	| isSpace c	= '_'
	| otherwise	= c

instance (Show v, Num c, Ord c) => Show (Constraint v c) where
	show (Constr lab func bds) = maybe "" (++ ": ") lab ++
		showBds (showFunc func) bds

instance (Read v, Ord v, Read c, Ord c, Num c) => Read (Constraint v c) where
	readsPrec _= readP_to_S $ liftM toConstr (lab <++ nolab) where
		toConstr (l, f, bds) = Constr l (fromList f) bds
		lab = do	skipSpaces
				label <- manyTill get (skipSpaces >> char ':')
				(_, f, bds) <- nolab
				return (Just label, f, bds)
		nolab = liftM (\ (f, bds) -> (Nothing, f, bds)) $ readBds readConst readFunc
		readFunc = (do	c <- readCoef readConst
				v <- readVar
				liftM ((v, c):) readFunc) <++ return []
		readConst = readS_to_P reads
		readVar = readS_to_P reads

readCoef :: Num c => ReadP c -> ReadP c
readCoef readC = between skipSpaces skipSpaces $ 
	(do	char '+'
		skipSpaces
		readC') <++
	(do	char '-'
		skipSpaces
		negate <$> readC') <++ readC'
	where	readC' = readC <++ return 1

optMaybe :: ReadP a -> ReadP (Maybe a)
optMaybe p = fmap Just p <++ return Nothing

readBds :: Ord c => ReadP c -> ReadP a -> ReadP (a, Bounds c)
readBds cst expr = do
	left <- optMaybe (do	lb <- cst
				skipSpaces
				rel <- readRelation
				return (lb, rel))
	skipSpaces
	f <- expr
	skipSpaces
	right <- optMaybe (do	rel <- readRelation
				skipSpaces
				ub <- cst
				return (ub, revOrd rel))
	return (f, getBd left `mappend` getBd right)
	where	revOrd :: Ordering -> Ordering
		revOrd GT = LT
		revOrd LT = GT
		revOrd EQ = EQ
		getBd :: Maybe (c, Ordering) -> Bounds c
		getBd Nothing = Free
		getBd (Just (x, cmp)) = case cmp of
			EQ	-> Equ x
			GT	-> LBound x
			LT	-> UBound x
		readRelation = choice [char '<' >> optional (char '=') >> return LT,
			char '=' >> return EQ,
			char '>' >> optional (char '=') >> return GT]

-- | Applies the specified function to the variables in the linear program.
-- If multiple variables in the original program are mapped to the same variable in the new program,
-- in general, we set those variables to all be equal, as follows.
-- * In linear functions, including the objective function and the constraints,
-- 	coefficients will be added together.  For instance, if @v1,v2@ are mapped to the same
-- 	variable @v'@, then a linear function of the form @c1 *& v1 ^+^ c2 *& v2@ will be mapped to
-- 	@(c1 ^+^ c2) *& v'@.
-- * In variable bounds, bounds will be combined.  An error will be thrown if the bounds
-- 	are mutually contradictory.
-- * In variable kinds, the most restrictive kind will be retained.
mapVars :: (Ord v', Ord c, Module r c) => (v -> v') -> LP v c -> LP v' c
mapVars f LP{..} =  
	LP{objective = mapKeysWith (^+^) f objective, 
		constraints = [Constr lab (mapKeysWith (^+^) f func) bd | Constr lab func bd <- constraints],
		varBounds = mapKeysWith mappend f varBounds,
		varTypes = mapKeysWith mappend f varTypes, ..}

-- | Applies the specified function to the constants in the linear program.  This is only safe
-- for a monotonic function.
mapVals :: (Ord c', Module r c') => (c -> c') -> LP v c -> LP v c'
mapVals = fmap

-- instance (NFData v, NFData c) => NFData (Constraint v c) where
-- 	rnf (Constr lab f b) = lab `deepseq` f `deepseq` rnf b

-- instance (NFData v, NFData c) => NFData (LP v c) where
-- 	rnf LP{..} = direction `deepseq` objective `deepseq` constraints `deepseq`
-- 		varBounds `deepseq` rnf varTypes