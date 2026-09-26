#pragma once

// Local shim for boost::connected_components over the adjacency_list shim: labels each vertex
// with its component and returns the number of components.
#include <boost_graph_adjacency_list.hpp>

namespace boost
{
template<typename O, typename V, typename D, typename ComponentMap>
int connected_components(const adjacency_list<O, V, D>& graph, ComponentMap components)
{
    const std::size_t count = graph.adjacency.size();
    std::vector<bool> seen(count, false);
    std::vector<std::size_t> stack;
    int components_found = 0;
    for (std::size_t start = 0; start < count; ++start) {
        if (seen[start]) {
            continue;
        }
        seen[start] = true;
        stack.push_back(start);
        while (!stack.empty()) {
            const std::size_t vertex = stack.back();
            stack.pop_back();
            components[vertex] = components_found;
            for (std::size_t neighbour : graph.adjacency[vertex]) {
                if (!seen[neighbour]) {
                    seen[neighbour] = true;
                    stack.push_back(neighbour);
                }
            }
        }
        ++components_found;
    }
    return components_found;
}
}  // namespace boost
