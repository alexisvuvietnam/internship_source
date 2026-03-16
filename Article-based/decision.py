import numpy as np
import pandas as pd
import itertools
from typing import List, Set

class BinaryDecision:
    def __init__(self, df, weights = []):
        self.data = df
        self.viewpoints = df.columns.values.to_numpy()
        self.alternatives = df.index.values.to_numpy()
        self.size = len(self.viewpoints)
        if len(weights) == 0:
            self.weights = [1] * self.size
        else:
            self.weights = weights

    def getUtility(self, alternative):
        assert (alternative in self.alternatives), "This alternative is not valid."
        utility = 0
        for i in range(self.size):
            utility += self.weights[i] * self.data[alternative][self.viewpoints[i]]
        return utility
    
    def getConditionalUtility(self, N, alternative):
        assert (alternative in self.alternatives), "This alternative is not valid."
        utility = 0
        for viewpoint in N:
            i = self.viewpoints.index(viewpoint)
            utility += self.weights[i] * self.data[alternative][viewpoint]
        return utility

    
    def preference(self, x, y):
        assert ((x in self.alternatives) and (y in self.alternatives)), "These alternatives are not valid."
        return self.getUtility(x) >= self.getUtility(y)
    
    def orientation(self, x, y):
        assert ((x in self.alternatives) and (y in self.alternatives)), "These alternatives are not valid."
        pros = set()
        cons = set()
        neutral = set()
        for viewpoint in self.viewpoints:
            if self.data[x][viewpoint] > self.data[y][viewpoint]:
                pros.add(viewpoint)
            elif self.data[x][viewpoint] < self.data[y][viewpoint]:
                cons.add(viewpoint)
            else:
                neutral.add(viewpoint)
        return pros, cons, neutral
    
    def trade_offs(self, np, nc, x, y):
        assert ((x in self.alternatives) and (y in self.alternatives)), "These alternatives are not valid."
        assert ((np >= 0) and (nc >= 0) and (x + y <= self.size)), "These parameters are not valid."
        pros, cons, _ = self.orientation(x, y)
        contextualized = list()
        tmp1 = itertools.combinations(pros, np)
        tmp2 = itertools.combinations(cons, nc)
        for P in tmp1:
            for C in tmp2:
                contextualized.append((P, C))
        return contextualized
    
    def trade_offs_disjointment(self, to1, to2):
        P1, C1 = to1
        P2, C2 = to2
        return P1.isdisjoint(P2) and C1.isdisjoint(C2)
    
    def trade_offs_alignment(self, to, x, y):
        P, C = to
        N = P | C
        return self.getConditionalUtility(N, x) >= self.getConditionalUtility(N, y)

class Solver:
    def __init__(self):
        pass