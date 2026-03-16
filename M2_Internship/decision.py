import numpy as np
import pandas as pd
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
    
    def preference(self, x, y):
        assert ((x in self.alternatives) and (y in self.alternatives)), "These alternatives are not valid."
        return self.getUtility(x) >= self.getUtility(y)
