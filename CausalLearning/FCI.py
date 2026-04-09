import pyagrum as gum
from dataclasses import dataclass
import itertools
import numpy as np
import pandas as pd
import graphviz
from pgmpy.estimators import CITests
import scipy

# FCI CLASS

class FCI:
    arrow_attributes = ["-", "o", ">"]
    dot_attributes = ["none", "odot", "normal"]

    def __init__(self, df, alpha=0.05, bayesnet=None):
        self.data = df
        self.variables = list(df.columns)
        self.n = len(self.variables)
        self.alpha = alpha

        self.bayesnet = bayesnet
        # Create BNLearner
        if self.bayesnet is not None:
            self.learner = gum.BNLearner(self.data, self.bayesnet)
        else:
            self.learner = gum.BNLearner(self.data)
        
        # Implement initial graph
        self.matrix = np.full((self.n, self.n), "o")
        for i in range(self.n):
            self.matrix[i, i] = " "

        # Separator sets
        self.separators = dict()
        for i in range(self.n):
            for j in range(self.n):
                if i != j:
                    self.separators[(i, j)] = set()

    def get_variables(self):
        return {key : value for key,value in enumerate(self.variables)}
    
    def exist_edge(self, i, j):
        if i == j: return False
        return self.matrix[i, j] != " " and self.matrix[j, i] != " "
    
    def remove_edge(self, i, j):
        if self.exist_edge(i, j):
            self.matrix[i, j] = " "
            self.matrix[j, i] = " "
    
    def list_adjacents(self, i):
        return set([j for j in range(self.n) if self.exist_edge(i, j)])
    
    def num_adjacents(self, i):
        return len(self.list_adjacents(i))
    
    def list_edges(self):
        L = []
        for i in range(self.n):
            for j in range(i + 1, self.n):
                if self.exist_edge(i, j):
                    L.append((i, j))
        return L

    def isIndependent(self, X, Y, Z, useGum=True):
        p = 0.0
        if useGum: _, p = self.learner.G2(X, Y, Z)
        else: _, p, _ = CITests.g_sq(X, Y, Z, self.data, boolean=False)
        return p > self.alpha

    def skeleton(self, useGum=True):
        d = 0
        flag = True
        while flag:
            edges = self.list_edges()
            flag = False
            for (i, j) in edges:
                if self.exist_edge(i, j):
                    adj_i = self.list_adjacents(i)
                    adj_j = self.list_adjacents(j)
                    check_list = [(j, adj_i), (i, adj_j)]
                    for (x, adj) in check_list:
                        if len(adj) > d:
                            flag = True
                            for Z in itertools.combinations([k for k in adj if k != x], d):
                                # print(f"skeleton {Z=}")
                                if self.isIndependent(self.variables[i], self.variables[j], [self.variables[k] for k in Z], useGum=useGum):
                                    self.separators[(i, j)] = set(Z)
                                    self.separators[(j, i)] = set(Z)
                                    self.remove_edge(i, j)
                                    break
            d += 1

    def get_separators(self):
        sep_set = self.separators.copy()
        result = dict()
        visited = []
        for i,j in sep_set.keys():
            if (i,j) not in visited or (j,i) not in visited:
                result[(i,j)]= self.separators[(i,j)].union(self.separators[(j,i)])
                visited.append((i,j))
                visited.append((j,i))
        return result

    def unshielded_triple_in_order_ijk(self, i, j, k):
        return self.exist_edge(i, j) and self.exist_edge(j, k) and not self.exist_edge(i, k)
    
    def get_unshielded_triples(self):
        output = set()
        for j in range(self.n):
            neighbors = self.list_adjacents(j)
            for i in neighbors:
                for k in neighbors:
                    if i != k:
                        if self.unshielded_triple_in_order_ijk(i, j, k):
                            output.add((i, j, k))
        return output
    
    def rule0(self, i, j, k):
        if self.unshielded_triple_in_order_ijk(i, j, k) and j not in self.separators[(i, k)]:
            self.matrix[i, j] = ">"
            self.matrix[k, j] = ">"

    def is_collider(self, i, j, k):
        return self.matrix[i, j] == ">" and self.matrix[k, j] == ">"
    
    def is_triangle(self, i, j, k):
        return self.exist_edge(i, j) and self.exist_edge(j, k) and self.exist_edge(i, k)
    
    def get_triangles(self):
        output = set()
        for j in range(self.n):
            neighbors = self.list_adjacents(j)
            for i in neighbors:
                for k in neighbors:
                    if i != k:
                        if self.is_triangle(i, j, k):
                            output.add((i, j, k))
        return output

    def is_parent(self, i, j):
        if self.exist_edge(i, j):
            return self.matrix[i, j] == ">" and self.matrix[j, i] == "-"
        return False

    def is_discriminating_path(self, path):
        if len(path) < 4:
            return False
        x = path[0]
        y = path[-1]
        v = path[-2]
        if self.exist_edge(x, y):
            return False
        if not self.exist_edge(v, y):
            return False
        for i in range(1, len(path) - 2):
            if not self.is_parent(path[i], y):
                return False
            if not self.is_collider(path[i - 1], path[i], path[i + 1]):
                return False
        return True
    
    def get_discriminating_paths_targeted(self, u, y, current_path, limit = 50):
        current_node = current_path[-1]
        if len(current_path) > limit: return []
        paths = []
        adjacents = self.list_adjacents(current_node)
        for node in adjacents:
            if node in current_path: continue
            if node == y:
                full_path = current_path + [y]
                if self.is_discriminating_path(full_path):
                    paths.append(full_path)
                continue
            new_path = current_path + [node]
            paths += self.get_discriminating_paths_targeted(u, y, new_path, limit=limit)
        return paths

    def list_discriminating_paths(self):
        all_results = []
        for u in range(self.n):
            for y in range(self.n):
                if u == y: continue
                if self.exist_edge(u, y): continue
                found_paths = self.get_discriminating_paths_targeted(u, y, [u])
                all_results.extend(found_paths)
        return all_results
    
    def get_possible_d_sep(self, from_node, to_node):
        queue = []
        visited = set()
        pds = set()
        adjacents = self.list_adjacents(from_node)
        for node in adjacents:
            if node != to_node:
                queue.append((node, from_node))
                visited.add((node, from_node))
                pds.add(node)
        while len(queue) > 0:
            curr, prev = queue.pop(0)
            adjacents_curr = self.list_adjacents(curr)
            for next_node in adjacents_curr:
                if next_node == prev:
                    continue
                if next_node == from_node:
                    continue
                if self.is_collider(prev, curr, next_node) or self.is_triangle(prev, curr, next_node):
                    if (next_node, curr) not in visited:
                        visited.add((next_node, curr))
                        queue.append((next_node, curr))
                        if next_node != to_node:
                            pds.add(next_node)
        return pds

    def refine_skeleton_with_pds(self, useGum=True):
        for i in range(self.n):
            pds = set()
            for j in range(self.n):
                pds = pds.union(self.get_possible_d_sep(i, j))
            pds = pds - {i}
            adjs = self.list_adjacents(i)
            for j in adjs:
                pds_j = pds - {j}
                flag = False
                for d in range(self.n - 1):
                    if len(pds_j) > d:
                        flag = True
                        for Z in itertools.combinations(pds_j, d):
                            if self.isIndependent(self.variables[i], self.variables[j], [self.variables[k] for k in Z], useGum=useGum):
                                self.separators[(i, j)] = self.separators[(i, j)].union(Z)
                                self.separators[(j, i)] = self.separators[(j, i)].union(Z)
                                self.remove_edge(i, j)
                                flag = False
                                break
                    if not flag: break
        self.matrix = np.where(self.matrix == " ", " ", "o")

    def rule1(self, v1, v2, v3):
        if self.unshielded_triple_in_order_ijk(v1, v2, v3):
            if self.matrix[v1, v2] == ">" and self.matrix[v3, v2] == "o":
                self.matrix[v3, v2] = "-"
                self.matrix[v2, v3] = ">"
    
    def rule2(self, v1, v2, v3):
        if self.is_triangle(v1, v2, v3):
            if self.matrix[v1, v2] == ">" and self.matrix[v2, v3] == ">" and (self.matrix[v2, v1] == "-" or self.matrix[v3, v2] == "-"):
                if self.matrix[v1, v3] == "o":
                    self.matrix[v1, v3] = ">"

    def rule3(self, v1, v2, v3, v4):
        if self.exist_edge(v1, v2) and self.exist_edge(v3, v2) and self.exist_edge(v4, v2) and self.exist_edge(v1, v4) and self.exist_edge(v3, v4) and not self.exist_edge(v1, v3):
            if self.matrix[v1, v2] == ">" and self.matrix[v3, v2] == ">" and self.matrix[v1, v4] == "o" and self.matrix[v3, v4] == "o" and self.matrix[v4, v2] == "o":
                self.matrix[v4, v2] = ">"

    def rule4(self, path):
        x = path[0]
        y = path[-1]
        v = path[-2]
        w = path[-3]
        if self.is_discriminating_path(path):
            if self.matrix[y, v] == "o":
                if v in self.separators[(x, y)]:
                    self.matrix[v, y] = ">"
                    self.matrix[y, v] = "-"
                else:
                    self.matrix[w, v] = ">"
                    self.matrix[v, w] = ">"
                    self.matrix[v, y] = ">"
                    self.matrix[y, v] = ">"

    def is_uncovered_path(self, path):
        for i in range(1, len(path) - 1):
            if self.exist_edge(path[i - 1], path[i + 1]):
                return False
        return True
    
    def is_circle_edge(self, i, j):
        return self.matrix[i, j] == "o" and self.matrix[j, i] == "o"
    
    def is_circle_path(self, path):
        for i in range(0, len(path) - 1):
            if not self.is_circle_edge(path[i], path[i + 1]):
                return False
        return True
    
    def is_pd_edge(self, i, j):
        return FCI.arrow_attributes.index(self.matrix[i, j]) >= FCI.arrow_attributes.index(self.matrix[j, i])
    
    def is_pd_path(self, path):
        for i in range(len(path) - 1):
            if not self.is_pd_edge(path[i], path[i + 1]):
                return False
        return True
    
    def get_uncovered_circle_paths_targeted(self, u, y, current_path, limit=10):
        current_node = current_path[-1]
        if len(current_path) > limit: return []
        adjacents = self.list_adjacents(current_node)
        paths = []
        for node in adjacents:
            if self.is_circle_edge(node, current_node):
                if node == y:
                    continue
                if node in current_path: 
                    continue
                if len(current_path) >= 2:
                    if not self.exist_edge(node, current_path[-2]):
                        if self.exist_edge(node, y):
                            if self.is_circle_edge(node, y) and not self.exist_edge(y, current_path[-1]): paths.append(current_path + [node] + [y])
                        else:
                            new_path = current_path + [node]
                            paths += self.get_uncovered_circle_paths_targeted(u, y, new_path, limit=limit)
                else:
                    if self.exist_edge(node, y):
                        if self.is_circle_edge(node, y) and not self.exist_edge(y, current_path[-1]): paths.append(current_path + [node] + [y])
                    else:
                        new_path = current_path + [node]
                        paths += self.get_uncovered_circle_paths_targeted(u, y, new_path, limit=limit)
        return paths
    
    def get_uncovered_pd_paths_targeted(self, u, y, current_path, limit=10):
        current_node = current_path[-1]
        if len(current_path) > limit: return []
        adjacents = self.list_adjacents(current_node)
        paths = []
        for node in adjacents:
            if self.is_pd_edge(node, current_node):
                if node == y:
                    continue
                if node in current_path: 
                    continue
                if len(current_path) >= 2:
                    if not self.exist_edge(node, current_path[-2]):
                        if self.exist_edge(node, y):
                            if self.is_pd_edge(node, y) and not self.exist_edge(y, current_path[-1]): paths.append(current_path + [node] + [y])
                        else:
                            new_path = current_path + [node]
                            paths += self.get_uncovered_pd_paths_targeted(u, y, new_path, limit=limit)
                else:
                    if self.exist_edge(node, y):
                        if self.is_pd_edge(node, y) and not self.exist_edge(y, current_path[-1]): paths.append(current_path + [node] + [y])
                    else:
                        new_path = current_path + [node]
                        paths += self.get_uncovered_pd_paths_targeted(u, y, new_path, limit=limit)
        return paths
    
    def rule5(self, x, y):
        if self.is_circle_edge(x, y):
            paths = self.get_uncovered_circle_paths_targeted(x, y, [x])
            for p in paths:
                if len(p) >= 4:
                    if not (self.exist_edge(x, p[-2]) or self.exist_edge(y, p[1])):
                        self.matrix[x, y] = "-"
                        self.matrix[y, x] = "-"
                        for i in range(0, len(p) - 1):
                            self.matrix[p[i], p[i + 1]] = "-"
                            self.matrix[p[i + 1], p[i]] = "-"
                    return

    def rule6(self, v1, v2, v3):
        if self.exist_edge(v1, v2) and self.exist_edge(v2, v3):
            if self.matrix[v1, v2] == "-" and self.matrix[v2, v1] == "-" and self.matrix[v3, v2] == "o":
                self.matrix[v3, v2] = "-"

    def rule7(self, v1, v2, v3):
        if self.exist_edge(v1, v2) and self.exist_edge(v2, v3) and not self.exist_edge(v1, v3):
            if self.matrix[v1, v2] == self.matrix[v2, v1] and self.matrix[v3, v2] == "o":
                self.matrix[v3, v2] = "-"

    def rule8(self, v1, v2, v3):
        if self.is_triangle(v1, v2, v3):
            if self.matrix[v2, v3] == ">" and self.matrix[v3, v2] == "-" and self.matrix[v2, v1] == "-" and self.matrix[v1, v2] != "-":
                if self.matrix[v1, v3] == ">":
                    if self.matrix[v3, v1] == "o": self.matrix[v3, v1] = "-"

    def rule9(self, v1, v2):
        if self.exist_edge(v1, v2):
            if self.matrix[v1, v2] == ">" and self.matrix[v2, v1] == "o":
                paths = self.get_uncovered_pd_paths_targeted(v1, v2, [v1])
                for p in paths:
                    if len(p) >= 4:
                        if not self.exist_edge(p[1], v2):
                            self.matrix[v2, v1] = "-"
                            return

    def rule10(self, alpha, gamma, beta, theta):
        if self.exist_edge(alpha, gamma) and self.exist_edge(beta, gamma) and self.exist_edge(theta, gamma):
            if self.matrix[alpha, gamma] == ">" and self.matrix[gamma, alpha] == "o" and self.matrix[beta, gamma] == ">" and self.matrix[gamma, beta] == "-" and self.matrix[theta, gamma] == ">" and self.matrix[gamma, theta] == "-":
                paths1 = self.get_uncovered_pd_paths_targeted(alpha, beta, [alpha], limit=self.n)
                paths2 = self.get_uncovered_pd_paths_targeted(alpha, theta, [alpha], limit=self.n)
                for p1 in paths1:
                    for p2 in paths2:
                        if p1[1] != p2[1] and not self.exist_edge(p1[1], p2[1]):
                            self.matrix[gamma, alpha] = "-"
                            return
                        
    def find_minimal_sepset(self, i, j, superset_indices):
        candidate_nodes = list(superset_indices)
        n_candidates = len(candidate_nodes)
        for r in range(n_candidates + 1):
            for Z in itertools.combinations(candidate_nodes, r):
                Z_list = list(Z)
                var_i = self.variables[i]
                var_j = self.variables[j]
                var_k = [self.variables[k] for k in Z_list]
                if self.isIndependent(var_i, var_j, var_k):
                    return set(Z_list)
        return set()
    
    def really_fast_v_orientation(self, useGum=True):
        L = []
        triplets = list(itertools.permutations(range(self.n), r=3))
        M = [(t[0], t[1], t[2]) for t in triplets if self.unshielded_triple_in_order_ijk(t[0], t[1], t[2])]
        while len(M) > 0:
            (i, j, k) = M.pop(0)
            if not (self.exist_edge(i, j) and self.exist_edge(j, k)):
                continue
            sep_ik = self.separators.get((i, k), set())
            cond_set_indices = sep_ik - {j}
            cond_set_variables = [self.variables[k] for k in cond_set_indices]
            is_dep_ij = self.isIndependent(self.variables[i], self.variables[j], cond_set_variables, useGum=useGum)
            is_dep_jk = self.isIndependent(self.variables[j], self.variables[k], cond_set_variables, useGum=useGum)
            if not (is_dep_ij or is_dep_jk):
                if (i, j, k) not in L:
                    L.append((i, j, k))
            else:
                pairs_to_check = []
                if not is_dep_ij:
                    pairs_to_check.append((i, j))
                if not is_dep_jk:
                    pairs_to_check.append((k, j))
                for (r, q) in pairs_to_check:
                    Y = self.find_minimal_sepset(r, q, cond_set_indices)
                    if len(Y) > 0:
                        self.separators[(r, q)] = Y
                        self.separators[(q, r)] = Y
                        adjacents_r = self.list_adjacents(r)
                        adjacents_q = self.list_adjacents(q)
                        common_adjacents = adjacents_r.intersection(adjacents_q)
                        for w in common_adjacents:
                            triple_new = (r, w, q)
                            if triple_new not in M: 
                                M.append(triple_new)
                        M = [t for t in M if not({r, q} < set(t))]
                        L = [t for t in L if not({r, q} < set(t))]
                        self.remove_edge(r, q)
        for (i, j, k) in L:
            if self.exist_edge(i, j) and self.exist_edge(j, k):
                sep_ik = self.separators[(i, k)]
                if j not in sep_ik:
                    self.matrix[i, j] = ">"
                    self.matrix[k, j] = ">"

    def rule4_rfci(self, path):
        if self.is_discriminating_path(path):
            u = path[0]
            y = path[-1]
            sepset_ik = self.separators.get((u, y), set())
            edge_removed_in_path = False
            for idx in range(len(path) - 1):
                r = path[idx]
                q = path[idx + 1]
                base_set = sepset_ik - {r, q}
                candidate_vars_indices = list(base_set)
                limit_l = len(candidate_vars_indices)
                found_indep = False
                found_Y = None
                for l in range(limit_l + 1):
                    for Z in itertools.combinations(candidate_vars_indices, l):
                        var_r = self.variables[r]
                        var_q = self.variables[q]
                        var_Z = [self.variables[zz] for zz in Z]
                        if self.isIndependent(var_r, var_q, var_Z):
                            found_indep = True
                            found_Y = set(Z)
                            break
                    if found_indep:
                        break
                if found_indep:
                    self.separators[(r, q)] = found_Y
                    self.separators[(q, r)] = found_Y
                    self.remove_edge(r, q)
                    self.really_fast_v_orientation()
                    edge_removed_in_path = True
                    break
            if not edge_removed_in_path:
                v = path[-2]
                if v in sepset_ik:
                    if self.matrix[v, y] != ">":
                        self.matrix[v, y] = ">"
                        self.matrix[y, v] = "-"
                else:
                    w = path[-3]
                    if self.matrix[w, v] != ">" or self.matrix[v, w] != ">":
                        self.matrix[w, v] = ">"
                        self.matrix[v, w] = ">"
                    if self.matrix[v, y] != ">" or self.matrix[y, v] != ">":
                        self.matrix[v, y] = ">"
                        self.matrix[y, v] = ">"


    def triangle_for_rfci(self, l, j, k):
        return self.is_triangle(l, j, k) and self.matrix[k, j] == "o" and self.matrix[j, l] == ">" and self.matrix[l, k] == ">" and self.matrix[k, l] == "-"

    def return_PDAG(self, opt=1):
        edges = set()
        arcs = set()
        if opt == 1:
            for i in range(self.n):
                for j in range(i + 1, self.n):
                    if self.exist_edge(i, j):
                        if self.matrix[i, j] == self.matrix[j, i]:
                            edges.add((i, j))
                        elif FCI.arrow_attributes.index(self.matrix[i, j]) > FCI.arrow_attributes.index(self.matrix[j, i]):
                            arcs.add((i, j))
                        else:
                            arcs.add((j, i))
        elif opt == 2:
            for i in range(self.n):
                for j in range(i + 1, self.n):
                    if self.exist_edge(i, j):
                        if self.matrix[i, j] == ">" and self.matrix[j, i] != ">":
                            arcs.add((i, j))
                        elif self.matrix[i, j] != ">" and self.matrix[j, i] == ">":
                            arcs.add((j, i))
                        else:
                            edges.add((i, j))
        elif opt == 3:
            for i in range(self.n):
                for j in range(i + 1, self.n):
                    if self.exist_edge(i, j):
                        if self.matrix[i, j] == ">" and self.matrix[j, i] == "-":
                            arcs.add((i, j))
                        elif self.matrix[i, j] == "-" and self.matrix[j, i] == ">":
                            arcs.add((j, i))
                        else:
                            edges.add((i, j))
        else: return None
        gum_graph = gum.PDAG()
        for i in range(self.n):
            gum_graph.addNodeWithId(i)
        for (i, j) in arcs:
            try:
                gum_graph.addArc(i, j)
            except:
                edges.add((i, j))
        for (i, j) in edges:
            try:
                gum_graph.addEdge(i, j)
            except:
                pass
        return gum_graph
    
    def get_certain_edges(self):
        return 
    
    def toDot(self):
        dot = graphviz.Digraph("Output PAG", node_attr={"shape": "oval", "fillcolor": "#333333", "textcolor": "#eeeeee"})
        dot.attr("node")
        for i in range(self.n):
            dot.node(self.variables[i], label=f"{self.variables[i]}")
        list_edges = self.list_edges()
        for (i, j) in list_edges:
            dot.edge(self.variables[i], self.variables[j], arrowtail=FCI.dot_attributes[FCI.arrow_attributes.index(self.matrix[j, i])], arrowhead=FCI.dot_attributes[FCI.arrow_attributes.index(self.matrix[i, j])], dir="both")
        return dot

def run_FCI(df, alpha=0.05, useGum=False, bayesnet=None):
    fci = FCI(df, alpha=alpha, bayesnet=bayesnet)
    fci.skeleton(useGum=useGum)
    M = fci.get_unshielded_triples()
    for t in M:
        fci.rule0(t[0], t[1], t[2])
    fci.refine_skeleton_with_pds(useGum=useGum)
    fci.matrix = np.where(fci.matrix == " ", " ", "o")
    M = fci.get_unshielded_triples()
    for t in M:
        fci.rule0(t[0], t[1], t[2])
    graph = fci.matrix
    old_graph = np.full((fci.n, fci.n), "")
    while not np.array_equal(old_graph, graph):
        old_graph = graph.copy()
        M = fci.get_unshielded_triples()
        for t in M:
            fci.rule1(t[0], t[1], t[2])
        T = fci.get_triangles()
        for t in T:
            fci.rule2(t[0], t[1], t[2])
        C = [t for t in itertools.permutations(range(fci.n), 4)]
        for t in C:
            fci.rule3(t[0], t[1], t[2], t[3])
        paths = fci.list_discriminating_paths()
        for path in paths:
            fci.rule4(path)
        graph = fci.matrix
    old_graph = np.full((fci.n, fci.n), "")
    while not np.array_equal(old_graph, graph):
        old_graph = graph.copy()
        circle_edges = [(x, y) for (x, y) in fci.list_edges() if fci.is_circle_edge(x, y)] + [(y, x) for (x, y) in fci.list_edges() if fci.is_circle_edge(x, y)]
        for (i, j) in circle_edges:
            fci.rule5(i, j)
        triplets = list(itertools.permutations(range(fci.n), 3))
        for t in triplets:
            fci.rule6(t[0], t[1], t[2])
        M = fci.get_unshielded_triples()
        for t in M:
            fci.rule7(t[0], t[1], t[2])
        tmp = fci.get_triangles()
        T = [t for t in tmp if fci.matrix[t[0], t[2]] == ">" and fci.matrix[t[2], t[0]] == "o"]
        for t in T:
            fci.rule8(t[0], t[1], t[2])
        couples = [(x, y) for (x, y) in fci.list_edges() if fci.matrix[x, y] == ">" and fci.matrix[y, x] == "o"] + [(x, y) for (y, x) in fci.list_edges() if fci.matrix[x, y] == ">" and fci.matrix[y, x] == "o"]
        for (x, y) in couples:
            fci.rule9(x, y)
        C = [t for t in itertools.permutations(range(fci.n), 4)]
        for t in C:
            fci.rule10(t[0], t[1], t[2], t[3])
        graph = fci.matrix
    return fci
        
def run_RFCI(df, alpha = 0.05, useGum=False, bayesnet=None):
    fci = FCI(df, alpha=alpha, bayesnet=bayesnet)
    fci.skeleton(useGum=useGum)
    fci.really_fast_v_orientation()
    graph = fci.matrix
    old_graph = np.full((fci.n, fci.n), "")
    while not np.array_equal(old_graph, graph):
        old_graph = graph.copy()
        M = fci.get_unshielded_triples()
        for t in M:
            fci.rule1(t[0], t[1], t[2])
        T = fci.get_triangles()
        for t in T:
            fci.rule2(t[0], t[1], t[2])
        C = [t for t in itertools.permutations(range(fci.n), 4)]
        for t in C:
            fci.rule3(t[0], t[1], t[2], t[3])
        potential_paths = fci.list_discriminating_paths()
        potential_paths.sort(key=len)
        for path in potential_paths:
            fci.rule4_rfci(path)
        circle_edges = [(x, y) for (x, y) in fci.list_edges() if fci.is_circle_edge(x, y)] + [(y, x) for (x, y) in fci.list_edges() if fci.is_circle_edge(x, y)]
        for (i, j) in circle_edges:
            fci.rule5(i, j)
        triplets = list(itertools.permutations(range(fci.n), 3))
        for t in triplets:
            fci.rule6(t[0], t[1], t[2])
        M = fci.get_unshielded_triples()
        for t in M:
            fci.rule7(t[0], t[1], t[2])
        tmp = fci.get_triangles()
        T = [t for t in tmp if fci.matrix[t[0], t[2]] == ">" and fci.matrix[t[2], t[0]] == "o"]
        for t in T:
            fci.rule8(t[0], t[1], t[2])
        couples = [(x, y) for (x, y) in fci.list_edges() if fci.matrix[x, y] == ">" and fci.matrix[y, x] == "o"] + [(x, y) for (y, x) in fci.list_edges() if fci.matrix[x, y] == ">" and fci.matrix[y, x] == "o"]
        for (x, y) in couples:
            fci.rule9(x, y)
        C = [t for t in itertools.permutations(range(fci.n), 4)]
        for t in C:
            fci.rule10(t[0], t[1], t[2], t[3])
        graph = fci.matrix
    return fci
    