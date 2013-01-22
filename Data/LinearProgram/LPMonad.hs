{-# LANGUAGE FlexibleContexts #-}

-- | A collection of operations that can be used to specify linear programming in a
-- simple, monadic way.  It is not too difficult to construct 'LP' values explicitly,
-- but this module may help simplify and modularize the construction of the linear program,
-- for example separating different families of constraints in the problem specification.
-- 
-- Many of these functions should be executed in either the @'LPM' v c@ or the @'LPT' v c 'IO'@ monad.
module Data.LinearProgram.LPMonad (
	module Data.LinearProgram.LPMonad.Internal,
	-- * Solvers
	quickSolveMIP,
	quickSolveLP,
	glpSolve,
	quickSolveMIP',
	quickSolveLP',
	glpSolve',
	-- * File I/O
	writeLPToFile,
	readLPFromFile,
	readLPFromFile') where

import Control.Monad ((<=<))
import Control.Monad.State.Class (MonadState(..))
import Control.Monad.Trans (MonadIO (..))

import Data.Map (Map)

import Data.LinearProgram.Common
import Data.LinearProgram.LPMonad.Internal

import Data.LinearProgram.GLPK.Solver
import Data.LinearProgram.GLPK.IO

{-# SPECIALIZE quickSolveLP :: (Ord v, Real c) => 
	LPT v c IO (ReturnCode, Maybe (Double, Map v Double)) #-}
{-# SPECIALIZE quickSolveMIP :: (Ord v, Real c) => 
	LPT v c IO (ReturnCode, Maybe (Double, Map v Double)) #-}
-- | Solves the linear program with the default settings in GLPK.  Returns the return code,
-- and if the solver was successful, the objective function value and the settings of each variable.
quickSolveLP, quickSolveMIP :: (Ord v, Real c, MonadState (LP v c) m, MonadIO m) => 
	m (ReturnCode, Maybe (Double, Map v Double))
quickSolveLP = glpSolve simplexDefaults
quickSolveMIP = glpSolve mipDefaults

{-# SPECIALIZE glpSolve :: (Ord v, Real c) => GLPOpts -> LPT v c IO (ReturnCode, Maybe (Double, Map v Double)) #-}
-- | Solves the linear program with the specified options in GLPK.  Returns the return code,
-- and if the solver was successful, the objective function value and the settings of each variable.
glpSolve :: (Ord v, Real c, MonadState (LP v c) m, MonadIO m) => GLPOpts -> m (ReturnCode, Maybe (Double, Map v Double))
glpSolve opts = get >>= liftIO . glpSolveVars opts

{-# SPECIALIZE quickSolveLP' :: (Ord v, Real c) => LPT v c IO (ReturnCode, Maybe (Double, Map v Double, [RowValue v c])) #-}
{-# SPECIALIZE quickSolveMIP' :: (Ord v, Real c) => LPT v c IO (ReturnCode, Maybe (Double, Map v Double, [RowValue v c])) #-}
-- | Solves the linear program with the default settings in GLPK.  Returns the return code,
-- and if the solver was successful, the objective function value, the settings of each variable, and the
-- value of each constraint/row.
quickSolveLP', quickSolveMIP' :: (Ord v, Real c, MonadState (LP v c) m, MonadIO m) => 
	m (ReturnCode, Maybe (Double, Map v Double, [RowValue v c]))
quickSolveLP' = glpSolve' simplexDefaults
quickSolveMIP' = glpSolve' mipDefaults

{-# SPECIALIZE glpSolve' :: (Ord v, Real c) => GLPOpts -> LPT v c IO (ReturnCode, Maybe (Double, Map v Double, [RowValue v c])) #-}
-- | Solves the linear program with the specified options in GLPK.  Returns the return code,
-- and if the solver was successful, the objective function value, the settings of each variable, and
-- the value of each constraint/row.
glpSolve' :: (Ord v, Real c, MonadState (LP v c) m, MonadIO m) => 
	GLPOpts -> m (ReturnCode, Maybe (Double, Map v Double, [RowValue v c]))
glpSolve' opts = get >>= liftIO . glpSolveAll opts

{-# SPECIALIZE writeLPToFile :: (Ord v, Show v, Real c) => FilePath -> LPT v c IO () #-}
-- | Writes the current linear program to the specified file in CPLEX LP format. 
-- (This is a binding to GLPK, not a Haskell implementation of CPLEX.)
writeLPToFile :: (Ord v, Show v, Real c, MonadState (LP v c) m, MonadIO m) =>
	FilePath -> m ()
writeLPToFile file = get >>= liftIO . writeLP file 

{-# SPECIALIZE readLPFromFile :: (Ord v, Read v, Ord c, Fractional c, Module r c) => FilePath -> LPT v c IO () #-}
-- | Reads a linear program from the specified file in CPLEX LP format, overwriting
-- the current linear program.  Uses 'read' and 'realToFrac' to translate to the specified type.
-- (This is a binding to GLPK, not a Haskell implementation of CPLEX.)
readLPFromFile :: (Ord v, Read v, Ord c, Fractional c, Module r c, MonadState (LP v c) m, MonadIO m) =>
	FilePath -> m ()
readLPFromFile = put . mapVars read . mapVals realToFrac <=< liftIO . execLPT . readLPFromFile'

{-# SPECIALIZE readLPFromFile :: FilePath -> LPT String Double IO () #-}
-- | Reads a linear program from the specified file in CPLEX LP format, overwriting
-- the current linear program.  (This is a binding to GLPK, not a Haskell implementation of CPLEX.)
readLPFromFile' :: (MonadState (LP String Double) m, MonadIO m) =>
	FilePath -> m ()
readLPFromFile' file = put =<< liftIO (readLP file)