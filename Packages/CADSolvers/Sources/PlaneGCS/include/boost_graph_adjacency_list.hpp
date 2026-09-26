#pragma once

// Local shim for the part of Boost.Graph's adjacency_list that PlaneGCS uses to partition the
// system into decoupled components.
#include <cstddef>
#include <vector>

namespace boost
{
struct vecS
{};
struct undirectedS
{};

template<typename OutEdgeList, typename VertexList, typename Directed>
struct adjacency_list
{
    std::vector<std::vector<std::size_t>> adjacency;
};

template<typename O, typename V, typename D>
std::size_t add_vertex(adjacency_list<O, V, D>& graph)
{
    graph.adjacency.emplace_back();
    return graph.adjacency.size() - 1;
}

template<typename O, typename V, typename D>
void add_edge(std::size_t a, std::size_t b, adjacency_list<O, V, D>& graph)
{
    graph.adjacency[a].push_back(b);
    graph.adjacency[b].push_back(a);
}

template<typename O, typename V, typename D>
std::size_t num_vertices(const adjacency_list<O, V, D>& graph)
{
    return graph.adjacency.size();
}
}  // namespace boost
